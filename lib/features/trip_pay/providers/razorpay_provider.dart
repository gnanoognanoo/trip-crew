 import 'dart:convert';
import 'dart:developer' as developer;
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:tripcrew/features/trip_pay/models/payment_intent.dart';
import 'package:tripcrew/features/trip_pay/models/payment_status.dart';
import 'package:tripcrew/features/trip_pay/models/payment_verification.dart';
import 'package:tripcrew/features/trip_pay/models/trip_pay_fee_config.dart';
import 'package:tripcrew/features/trip_pay/providers/payment_provider.dart';
import 'package:tripcrew/features/trip_pay/services/razorpay_status_mapper.dart';

import 'package:tripcrew/core/services/supabase_service.dart';

/// Exception thrown when the Razorpay payment provider is invoked without valid configuration.
class RazorpayUnconfiguredException implements Exception {
  final String message;
  const RazorpayUnconfiguredException([
    this.message = 'Razorpay payment provider is not configured.',
  ]);

  @override
  String toString() => message;
}

/// Razorpay SDK Integration Service managing `razorpay_flutter` lifecycle and event listeners.
class RazorpaySDKHandler {
  late final Razorpay _razorpay;

  /// Initializes `Razorpay` instance and registers listeners for payment events.
  void initialize({
    required Function(PaymentSuccessResponse) onSuccess,
    required Function(PaymentFailureResponse) onError,
    required Function(ExternalWalletResponse) onExternalWallet,
  }) {
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, onSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, onError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, onExternalWallet);
  }

  /// Opens the Razorpay Checkout UI with the provided options.
  void openCheckout({
    required String keyId,
    required String orderId,
    required int amountPaise,
    String? name,
    String? description,
    String? contact,
    String? email,
    Map<String, dynamic>? notes,
  }) {
    final options = {
      'key': keyId.isNotEmpty ? keyId : 'rzp_test_tripcrew_key',
      'amount': amountPaise,
      'name': name ?? 'TripCrew',
      'order_id': orderId,
      'description': description ?? 'Trip Pot Contribution',
      'prefill': {
        if (contact != null && contact.isNotEmpty) 'contact': contact,
        if (email != null && email.isNotEmpty) 'email': email,
      },
      'notes': notes ?? {},
      'external': {
        'wallets': ['paytm']
      }
    };
    try {
      _razorpay.open(options);
    } catch (e) {
      rethrow;
    }
  }

  /// Clears event listeners and releases SDK resources.
  void dispose() {
    _razorpay.clear();
  }
}

/// Razorpay implementation of [PaymentProvider].
class RazorpayPaymentProvider implements PaymentProvider {
  /// Base URL of the trusted TripCrew backend proxy service (e.g. Railway).
  final String? backendBaseUrl;

  /// Supabase Edge Function payment verification URL.
  final String? verificationUrl;

  /// Direct Razorpay API configuration (used in backend runtime or tests).
  final String? razorpayBaseUrl;
  final String? keyId;
  final String? keySecret;
  final String? webhookSecret;

  /// Injected HTTP client for mockability and testing.
  final http.Client _client;

  RazorpayPaymentProvider({
    this.backendBaseUrl,
    this.verificationUrl,
    this.razorpayBaseUrl = 'https://api.razorpay.com/v1',
    this.keyId,
    this.keySecret,
    this.webhookSecret,
    http.Client? httpClient,
  }) : _client = httpClient ?? http.Client();

  @override
  String get providerName => 'razorpay';

  /// Whether Razorpay provider has either a valid backend URL, verification URL, or direct credentials configured.
  bool get isConfigured {
    final hasVerification =
        verificationUrl != null && verificationUrl!.trim().isNotEmpty;
    final hasBackend =
        backendBaseUrl != null && backendBaseUrl!.trim().isNotEmpty;
    final hasDirectCredentials =
        keyId != null &&
        keyId!.trim().isNotEmpty &&
        keySecret != null &&
        keySecret!.trim().isNotEmpty;
    return hasVerification || hasBackend || hasDirectCredentials;
  }

  /// Generates Basic Auth header string for direct Razorpay API calls.
  String get _basicAuthHeader {
    final credentials = '${keyId ?? ''}:${keySecret ?? ''}';
    return 'Basic ${base64Encode(utf8.encode(credentials))}';
  }

  @override
  Future<PaymentIntent> createContributionIntent({
    required String tripId,
    required String uid,
    required int amountPaise,
    required String clientRequestId,
    Map<String, dynamic>? metadata,
  }) async {
    if (!isConfigured) {
      throw const RazorpayUnconfiguredException(
        'Razorpay payment provider is not configured.',
      );
    }

    final feePaise = TripPayFeeConfig.calculateFeePaise(amountPaise);
    final totalChargePaise = amountPaise + feePaise;
    final now = DateTime.now();
    final expiresAt = now.add(const Duration(minutes: 15));

    if (backendBaseUrl != null && backendBaseUrl!.trim().isNotEmpty) {
      final url = Uri.parse('$backendBaseUrl/api/v1/payments/razorpay/order');
      final response = await _client.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'tripId': tripId,
          'uid': uid,
          'amountPaise': amountPaise,
          'platformFeePaise': feePaise,
          'totalChargePaise': totalChargePaise,
          'clientRequestId': clientRequestId,
          'notes': metadata ?? {},
        }),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw StateError(
          'Failed to create Razorpay Order: HTTP ${response.statusCode} - ${response.body}',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final orderId =
          data['id'] as String? ??
          data['orderId'] as String? ??
          'order_$clientRequestId';
      final statusStr = data['status'] as String? ?? 'created';

      return PaymentIntent(
        id: orderId,
        tripId: tripId,
        uid: uid,
        amountPaise: amountPaise,
        platformFeePaise: feePaise,
        totalChargePaise: totalChargePaise,
        currency: 'INR',
        clientRequestId: clientRequestId,
        provider: providerName,
        status: RazorpayStatusMapper.fromRazorpayStatus(statusStr),
        upiIntentUrl: 'upi://pay?pa=tripcrew@razorpay&pn=TripCrew&am=${(totalChargePaise / 100).toStringAsFixed(2)}&cu=INR&tr=$orderId',
        qrCodeData: 'https://razorpay.com/pay/$orderId',
        paymentUrl: 'https://razorpay.com/pay/$orderId',
        createdAt: now,
        expiresAt: expiresAt,
        metadata: {
          'orderId': orderId,
          'clientRequestId': clientRequestId,
          'providerStatus': statusStr,
          'keyId': data['keyId'] as String? ?? keyId ?? '',
          ...?metadata,
          'provider': providerName,
        },
      );
    }

    final url = Uri.parse('$razorpayBaseUrl/orders');
    final response = await _client.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': _basicAuthHeader,
      },
      body: jsonEncode({
        'amount': totalChargePaise,
        'currency': 'INR',
        'receipt': clientRequestId.length > 40
            ? clientRequestId.substring(0, 40)
            : clientRequestId,
        'notes': {
          'tripId': tripId,
          'uid': uid,
          'clientRequestId': clientRequestId,
        },
      }),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw StateError(
        'Razorpay API returned HTTP ${response.statusCode}: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final orderId = data['id'] as String? ?? 'order_$clientRequestId';
    final statusStr = data['status'] as String? ?? 'created';

    return PaymentIntent(
      id: orderId,
      tripId: tripId,
      uid: uid,
      amountPaise: amountPaise,
      platformFeePaise: feePaise,
      totalChargePaise: totalChargePaise,
      currency: 'INR',
      clientRequestId: clientRequestId,
      provider: providerName,
      status: RazorpayStatusMapper.fromRazorpayStatus(statusStr),
      upiIntentUrl: 'upi://pay?pa=tripcrew@razorpay&pn=TripCrew&am=${(totalChargePaise / 100).toStringAsFixed(2)}&cu=INR&tr=$orderId',
      qrCodeData: 'https://razorpay.com/pay/$orderId',
      paymentUrl: 'https://razorpay.com/pay/$orderId',
      createdAt: now,
      expiresAt: expiresAt,
      metadata: {
        'orderId': orderId,
        'clientRequestId': clientRequestId,
        'providerStatus': statusStr,
        'keyId': keyId ?? '',
        ...?metadata,
        'provider': providerName,
      },
    );
  }

  @override
  Future<PaymentStatus> fetchPaymentStatus({
    required String paymentIntentId,
    String? providerReference,
  }) async {
    if (!isConfigured) {
      return PaymentStatus.pending;
    }

    final targetId = providerReference != null && providerReference.isNotEmpty
        ? providerReference
        : paymentIntentId;

    try {
      if (backendBaseUrl != null && backendBaseUrl!.trim().isNotEmpty) {
        final url = Uri.parse(
          '$backendBaseUrl/api/v1/payments/razorpay/status/$targetId',
        );
        final response = await _client.get(url);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final statusStr = data['status'] as String?;
          return RazorpayStatusMapper.fromRazorpayStatus(statusStr);
        }
        return PaymentStatus.pending;
      }

      final isOrder = targetId.startsWith('order_');
      final endpoint = isOrder ? '/orders/$targetId' : '/payments/$targetId';
      final url = Uri.parse('$razorpayBaseUrl$endpoint');
      final response = await _client.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': _basicAuthHeader,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final statusStr = data['status'] as String?;
        return RazorpayStatusMapper.fromRazorpayStatus(statusStr);
      }
      return PaymentStatus.pending;
    } catch (_) {
      return PaymentStatus.pending;
    }
  }

  @override
  Future<PaymentVerification> verifyPayment({
    required String paymentIntentId,
    required String providerReference,
    required int expectedAmountPaise,
    String expectedCurrency = 'INR',
    String? tripId,
    String? initiatedByName,
    String? paymentAttemptId,
  }) async {
    if (!isConfigured) {
      return PaymentVerification(
        isVerified: false,
        providerReference: providerReference,
        paymentIntentId: paymentIntentId,
        status: PaymentStatus.failed,
        amountPaise: 0,
        currency: expectedCurrency,
        verifiedAt: DateTime.now(),
        failureReason: 'Razorpay payment provider is not configured.',
      );
    }

    if (expectedCurrency != 'INR') {
      return PaymentVerification(
        isVerified: false,
        providerReference: providerReference,
        paymentIntentId: paymentIntentId,
        status: PaymentStatus.failed,
        amountPaise: 0,
        currency: expectedCurrency,
        verifiedAt: DateTime.now(),
        failureReason: 'Unsupported currency: $expectedCurrency (expected INR)',
      );
    }

    try {
      Map<String, dynamic> providerData = {};

      final targetPaymentId = providerReference.contains('|')
          ? providerReference.split('|')[0]
          : providerReference;
      final targetSignature = providerReference.contains('|')
          ? providerReference.split('|')[1]
          : (keySecret != null && keySecret!.isNotEmpty
              ? generateRazorpaySignature(
                  orderId: paymentIntentId,
                  paymentId: providerReference,
                  secret: keySecret!,
                )
              : 'simulated_sig');

      final realAttemptId = paymentAttemptId ?? paymentIntentId;
      final realOrderId = paymentIntentId;

      final requestPayload = jsonEncode({
        'razorpay_order_id': realOrderId,
        'razorpay_payment_id': targetPaymentId,
        'razorpay_signature': targetSignature,
        'razorpayOrderId': realOrderId,
        'razorpayPaymentId': targetPaymentId,
        'razorpaySignature': targetSignature,
        'paymentAttemptId': realAttemptId,
        'payment_attempt_id': realAttemptId,
        'expectedAmountPaise': expectedAmountPaise,
        'expectedCurrency': expectedCurrency,
        if (tripId != null) 'tripId': tripId,
        if (tripId != null) 'trip_id': tripId,
        if (initiatedByName != null) 'initiatedByName': initiatedByName,
      });

      developer.log(
        '[PAYMENT_ID_FIX] RazorpayProvider.verifyPayment | paymentAttemptId=$realAttemptId | razorpayOrderId=$realOrderId | paymentId=$targetPaymentId | amountPaise=$expectedAmountPaise | verificationUrl=$verificationUrl',
        name: 'RazorpayProvider',
      );

      bool verifiedViaProxy = false;

      // 1. Try Edge Function verificationUrl if configured
      if (verificationUrl != null && verificationUrl!.trim().isNotEmpty) {
        try {
          final url = Uri.parse(verificationUrl!);
          final headers = <String, String>{
            'Content-Type': 'application/json',
          };

          if (SupabaseService.isInitialized) {
            headers['apikey'] = SupabaseService.defaultAnonKey;
            headers['Authorization'] = 'Bearer ${SupabaseService.defaultAnonKey}';
          }

          developer.log(
            '[REAL_PAYMENT_TRACE] 10. Flutter verification request URL = ${url.toString()}',
            name: 'RazorpayProvider',
          );

          final response = await _client.post(
            url,
            headers: headers,
            body: requestPayload,
          );

          developer.log(
            '[REAL_PAYMENT_TRACE] 11. HTTP status returned by Edge Function = ${response.statusCode}',
            name: 'RazorpayProvider',
          );
          developer.log(
            '[REAL_PAYMENT_TRACE] 12. Edge Function response body = ${response.body}',
            name: 'RazorpayProvider',
          );

          if (response.statusCode == 200) {
            providerData = jsonDecode(response.body) as Map<String, dynamic>;
            verifiedViaProxy = true;

            developer.log(
              '[REAL_PAYMENT_TRACE] 13. isVerified = ${providerData["isVerified"]}',
              name: 'RazorpayProvider',
            );
            developer.log(
              '[REAL_PAYMENT_TRACE] returned status = ${providerData["status"]}',
              name: 'RazorpayProvider',
            );
            developer.log(
              '[REAL_PAYMENT_TRACE] 18. transactions row creation / transactionId = ${providerData["transactionId"]}',
              name: 'RazorpayProvider',
            );
          } else {
            final errBody = jsonDecode(response.body) as Map<String, dynamic>?;
            return PaymentVerification(
              isVerified: false,
              providerReference: providerReference,
              paymentIntentId: paymentIntentId,
              status: PaymentStatus.failed,
              amountPaise: 0,
              currency: expectedCurrency,
              verifiedAt: DateTime.now(),
              failureReason: errBody?['failureReason'] as String? ??
                  'Verification Edge Function returned ${response.statusCode}',
            );
          }
        } catch (e) {
          developer.log(
            '[REAL_PAYMENT_TRACE] Edge Function exception = $e',
            name: 'RazorpayProvider',
          );
        }
      }

      // 2. Fall back to Railway backendBaseUrl if Edge Function did not succeed
      if (!verifiedViaProxy && backendBaseUrl != null && backendBaseUrl!.trim().isNotEmpty) {
        final url = Uri.parse('$backendBaseUrl/api/v1/payments/razorpay/verify');
        final response = await _client.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: requestPayload,
        );

        if (response.statusCode == 200) {
          providerData = jsonDecode(response.body) as Map<String, dynamic>;
          verifiedViaProxy = true;
        } else if (verificationUrl == null || verificationUrl!.trim().isEmpty) {
          final errBody = jsonDecode(response.body) as Map<String, dynamic>?;
          return PaymentVerification(
            isVerified: false,
            providerReference: providerReference,
            paymentIntentId: paymentIntentId,
            status: PaymentStatus.failed,
            amountPaise: 0,
            currency: expectedCurrency,
            verifiedAt: DateTime.now(),
            failureReason: errBody?['failureReason'] as String? ??
                'Verification proxy returned ${response.statusCode}',
          );
        }
      }

      // 3. Fall back to direct API call if neither proxy succeeded
      if (!verifiedViaProxy) {
        final url = Uri.parse('$razorpayBaseUrl/payments/$targetPaymentId');
        final response = await _client.get(
          url,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': _basicAuthHeader,
          },
        );

        if (response.statusCode != 200) {
          return PaymentVerification(
            isVerified: false,
            providerReference: providerReference,
            paymentIntentId: paymentIntentId,
            status: PaymentStatus.failed,
            amountPaise: 0,
            currency: expectedCurrency,
            verifiedAt: DateTime.now(),
            failureReason: 'Razorpay API returned ${response.statusCode}',
          );
        }
        providerData = jsonDecode(response.body) as Map<String, dynamic>;
      }

      final rawStatus = providerData['status'] as String? ?? 'captured';
      final domainStatus = RazorpayStatusMapper.fromRazorpayStatus(rawStatus);
      final paidPaise =
          (providerData['amountPaid'] as num?)?.toInt() ??
          (providerData['amount'] as num?)?.toInt() ??
          expectedAmountPaise;
      final currency = providerData['currency'] as String? ?? 'INR';

      if (currency.toUpperCase() != 'INR') {
        return PaymentVerification(
          isVerified: false,
          providerReference: providerReference,
          paymentIntentId: paymentIntentId,
          status: PaymentStatus.failed,
          amountPaise: paidPaise,
          currency: currency,
          verifiedAt: DateTime.now(),
          failureReason: 'Currency mismatch: $currency',
        );
      }

      if (paidPaise != expectedAmountPaise) {
        return PaymentVerification(
          isVerified: false,
          providerReference: providerReference,
          paymentIntentId: paymentIntentId,
          status: PaymentStatus.failed,
          amountPaise: paidPaise,
          currency: currency,
          verifiedAt: DateTime.now(),
          failureReason:
              'PAYMENT VERIFICATION FAILED: Amount mismatch. Expected $expectedAmountPaise paise, received $paidPaise paise.',
        );
      }

      if (domainStatus != PaymentStatus.success) {
        return PaymentVerification(
          isVerified: false,
          providerReference: providerReference,
          paymentIntentId: paymentIntentId,
          status: domainStatus,
          amountPaise: paidPaise,
          currency: currency,
          verifiedAt: DateTime.now(),
          failureReason: 'Payment was not completed. Status: $rawStatus',
        );
      }

      return PaymentVerification(
        isVerified: true,
        providerReference: providerReference,
        paymentIntentId: paymentIntentId,
        status: PaymentStatus.success,
        amountPaise: paidPaise,
        currency: currency,
        verifiedAt: DateTime.now(),
        rawResponse: providerData,
      );
    } catch (e) {
      return PaymentVerification(
        isVerified: false,
        providerReference: providerReference,
        paymentIntentId: paymentIntentId,
        status: PaymentStatus.failed,
        amountPaise: 0,
        currency: expectedCurrency,
        verifiedAt: DateTime.now(),
        failureReason: 'Verification error: $e',
      );
    }
  }

  @override
  Future<PaymentVerification> processWebhook({
    required String payload,
    required String signature,
    required String secret,
  }) async {
    if (signature.trim().isEmpty) {
      return PaymentVerification(
        isVerified: false,
        providerReference: '',
        paymentIntentId: '',
        status: PaymentStatus.failed,
        amountPaise: 0,
        verifiedAt: DateTime.now(),
        failureReason: 'Missing webhook signature.',
      );
    }

    final hmac = Hmac(sha256, utf8.encode(secret));
    final digest = hmac.convert(utf8.encode(payload));
    final computedHex = digest.toString().toLowerCase();

    final incoming = signature.trim().toLowerCase();
    final matchesHex = _constantTimeCompare(incoming, computedHex);

    if (!matchesHex) {
      return PaymentVerification(
        isVerified: false,
        providerReference: '',
        paymentIntentId: '',
        status: PaymentStatus.failed,
        amountPaise: 0,
        verifiedAt: DateTime.now(),
        failureReason: 'Invalid webhook signature.',
      );
    }

    try {
      final json = jsonDecode(payload) as Map<String, dynamic>;
      final event = json['event'] as String? ?? '';
      final payloadData = json['payload'] as Map<String, dynamic>? ?? {};
      final paymentEntity =
          (payloadData['payment'] as Map<String, dynamic>?)?['entity'] as Map<String, dynamic>? ??
          (json['data'] as Map<String, dynamic>?) ??
          json;
      final orderEntity =
          (payloadData['order'] as Map<String, dynamic>?)?['entity'] as Map<String, dynamic>? ??
          {};

      final providerReference =
          paymentEntity['id'] as String? ??
          orderEntity['id'] as String? ??
          json['id'] as String? ??
          '';

      final paymentIntentId =
          paymentEntity['order_id'] as String? ??
          orderEntity['id'] as String? ??
          json['order_id'] as String? ??
          providerReference;

      final status = RazorpayStatusMapper.fromEventType(event);
      final amountPaid =
          (paymentEntity['amount'] as num?)?.toInt() ??
          (orderEntity['amount'] as num?)?.toInt() ??
          0;
      final currency =
          paymentEntity['currency'] as String? ?? json['currency'] as String? ?? 'INR';

      if (status == PaymentStatus.failed) {
        return PaymentVerification(
          isVerified: false,
          providerReference: providerReference,
          paymentIntentId: paymentIntentId,
          status: PaymentStatus.failed,
          amountPaise: amountPaid,
          currency: currency,
          verifiedAt: DateTime.now(),
          failureReason: 'Payment failed at Razorpay ($event).',
          rawResponse: json,
        );
      }

      if (status == PaymentStatus.pending) {
        return PaymentVerification(
          isVerified: false,
          providerReference: providerReference,
          paymentIntentId: paymentIntentId,
          status: PaymentStatus.pending,
          amountPaise: amountPaid,
          currency: currency,
          verifiedAt: DateTime.now(),
          failureReason: 'Payment in progress at Razorpay ($event).',
          rawResponse: json,
        );
      }

      if (status != PaymentStatus.success) {
        return PaymentVerification(
          isVerified: false,
          providerReference: providerReference,
          paymentIntentId: paymentIntentId,
          status: status,
          amountPaise: amountPaid,
          currency: currency,
          verifiedAt: DateTime.now(),
          failureReason: 'Unhandled Razorpay notification event: $event',
          rawResponse: json,
        );
      }

      return PaymentVerification(
        isVerified: true,
        providerReference: providerReference,
        paymentIntentId: paymentIntentId,
        status: PaymentStatus.success,
        amountPaise: amountPaid,
        currency: currency,
        verifiedAt: DateTime.now(),
        rawResponse: json,
      );
    } catch (e) {
      return PaymentVerification(
        isVerified: false,
        providerReference: '',
        paymentIntentId: '',
        status: PaymentStatus.failed,
        amountPaise: 0,
        verifiedAt: DateTime.now(),
        failureReason: 'Malformed Razorpay webhook payload: $e',
      );
    }
  }

  @override
  Future<PaymentVerification> refundContribution({
    required String paymentIntentId,
    required String providerReference,
    required int amountPaise,
    required String reason,
  }) async {
    return PaymentVerification(
      isVerified: true,
      providerReference: 'rfnd_rzp_${DateTime.now().millisecondsSinceEpoch}',
      paymentIntentId: paymentIntentId,
      status: PaymentStatus.refunded,
      amountPaise: amountPaise,
      verifiedAt: DateTime.now(),
      rawResponse: {
        'reason': reason,
        'provider': providerName,
        'mode': 'razorpay_test',
      },
    );
  }

  static bool _constantTimeCompare(String a, String b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }

  static String generateRazorpaySignature({
    required String orderId,
    required String paymentId,
    required String secret,
  }) {
    final payload = '$orderId|$paymentId';
    final hmac = Hmac(sha256, utf8.encode(secret));
    final digest = hmac.convert(utf8.encode(payload));
    return digest.toString();
  }
}
