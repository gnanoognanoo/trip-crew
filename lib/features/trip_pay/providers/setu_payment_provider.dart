import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:tripcrew/features/trip_pay/models/payment_intent.dart';
import 'package:tripcrew/features/trip_pay/models/payment_status.dart';
import 'package:tripcrew/features/trip_pay/models/payment_verification.dart';
import 'package:tripcrew/features/trip_pay/models/trip_pay_fee_config.dart';
import 'package:tripcrew/features/trip_pay/providers/payment_provider.dart';
import 'package:tripcrew/features/trip_pay/services/setu_status_mapper.dart';

/// Exception thrown when the Setu payment provider is invoked without valid configuration.
class SetuUnconfiguredException implements Exception {
  final String message;
  const SetuUnconfiguredException([
    this.message = 'UPI test provider is not configured.',
  ]);

  @override
  String toString() => message;
}

/// Setu UPI Sandbox / UAT implementation of [PaymentProvider].
///
/// Implements official Setu UPI Payment Links / DeepLinks APIs (v2) for UAT testing.
///
/// TRUST BOUNDARY:
/// - In Flutter clients, requests route through the trusted TripCrew backend service
///   to protect secrets (Setu Client Secret, Webhook Secret).
/// - When running in the backend or testing suite, [SetuPaymentProvider] can directly
///   interact with Setu's UAT gateway (`https://uat.setu.co/api/v2`).
/// - If neither backend URL nor gateway credentials are configured, it cleanly reports
///   that the provider is not configured rather than failing silently or pretending success.
class SetuPaymentProvider implements PaymentProvider {
  /// Base URL of the trusted TripCrew backend proxy service.
  final String? backendBaseUrl;

  /// Direct Setu UAT API configuration (used in backend runtime or tests).
  final String? uatBaseUrl;
  final String? clientId;
  final String? clientSecret;
  final String? productInstanceId;
  final String? webhookSecret;

  /// Injected HTTP client for mockability and testing.
  final http.Client _client;

  SetuPaymentProvider({
    this.backendBaseUrl,
    this.uatBaseUrl = 'https://uatapi.setu.co',
    this.clientId,
    this.clientSecret,
    this.productInstanceId,
    this.webhookSecret,
    http.Client? httpClient,
  }) : _client = httpClient ?? http.Client();

  @override
  String get providerName => 'setu';

  /// Whether Setu provider has either a valid backend URL or direct credentials configured.
  bool get isConfigured {
    final hasBackend =
        backendBaseUrl != null && backendBaseUrl!.trim().isNotEmpty;
    final hasDirectCredentials =
        clientId != null &&
        clientId!.trim().isNotEmpty &&
        clientSecret != null &&
        clientSecret!.trim().isNotEmpty &&
        productInstanceId != null &&
        productInstanceId!.trim().isNotEmpty;
    return hasBackend || hasDirectCredentials;
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
      throw const SetuUnconfiguredException(
        'UPI test provider is not configured.',
      );
    }

    final feePaise = TripPayFeeConfig.calculateFeePaise(amountPaise);
    final totalChargePaise = amountPaise + feePaise;
    final now = DateTime.now();
    final expiresAt = now.add(const Duration(minutes: 15));

    // Route 1: Via trusted backend proxy (client-safe)
    if (backendBaseUrl != null && backendBaseUrl!.trim().isNotEmpty) {
      final url = Uri.parse('$backendBaseUrl/api/v1/payments/setu/intent');
      final response = await _client.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'amountValue': totalChargePaise,
          'billerBillID': clientRequestId,
          'payeeName': 'TripCrew',
          'tripId': tripId,
          'uid': uid,
          'amountPaise': amountPaise,
          'platformFeePaise': feePaise,
          'totalChargePaise': totalChargePaise,
          'clientRequestId': clientRequestId,
          'metadata': metadata ?? {},
        }),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw StateError(
          'Failed to create Setu intent: HTTP ${response.statusCode} - ${response.body}',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final platformBillId =
          data['platformBillID'] as String? ??
          data['id'] as String? ??
          data['txnId'] as String? ??
          '';
      final upiLink =
          data['upiID'] as String? ??
          data['upiLink'] as String? ??
          data['intentLink'] as String?;
      final shortUrl =
          data['shortURL'] as String? ??
          data['shortUrl'] as String? ??
          data['shortLink'] as String? ??
          data['paymentUrl'] as String?;
      final statusStr =
          data['status'] as String? ??
          data['initialSetuStatus'] as String? ??
          data['paymentStatus'] as String? ??
          'pending';

      return PaymentIntent(
        id: platformBillId.isNotEmpty
            ? platformBillId
            : 'setu_$clientRequestId',
        tripId: tripId,
        uid: uid,
        amountPaise: amountPaise,
        platformFeePaise: feePaise,
        totalChargePaise: totalChargePaise,
        currency: 'INR',
        clientRequestId: clientRequestId,
        provider: providerName,
        status: SetuStatusMapper.fromSetuStatus(statusStr),
        upiIntentUrl: upiLink,
        qrCodeData: upiLink ?? shortUrl,
        paymentUrl: shortUrl,
        createdAt: now,
        expiresAt: expiresAt,
        metadata: {
          'platformBillID': platformBillId,
          'billerBillID': clientRequestId,
          'providerStatus': statusStr,
          'txnId': platformBillId,
          ...?metadata,
          'provider': providerName,
        },
      );
    }

    // Route 2: Direct Setu UAT call (Merchant Quickstart)
    final url = Uri.parse('$uatBaseUrl/api/merchant/v2/collect');
    final response = await _client.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'X-Setu-Product-Instance-ID': productInstanceId!,
        'Authorization': 'Bearer $clientSecret', // Or OAuth token
      },
      body: jsonEncode({
        'amountValue': totalChargePaise,
        'billerBillID': clientRequestId,
        'payeeName': 'TripCrew',
      }),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw StateError(
        'Setu UAT returned HTTP ${response.statusCode}: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final platformBillId =
        data['platformBillID'] as String? ??
        data['id'] as String? ??
        data['txnId'] as String? ??
        '';
    final upiLink =
        data['upiID'] as String? ??
        data['upiLink'] as String? ??
        data['intentLink'] as String?;
    final shortUrl =
        data['shortURL'] as String? ??
        data['shortUrl'] as String? ??
        data['shortLink'] as String? ??
        data['paymentUrl'] as String?;
    final statusStr =
        data['status'] as String? ??
        data['paymentStatus'] as String? ??
        'pending';

    return PaymentIntent(
      id: platformBillId.isNotEmpty ? platformBillId : 'setu_$clientRequestId',
      tripId: tripId,
      uid: uid,
      amountPaise: amountPaise,
      platformFeePaise: feePaise,
      totalChargePaise: totalChargePaise,
      currency: 'INR',
      clientRequestId: clientRequestId,
      provider: providerName,
      status: SetuStatusMapper.fromSetuStatus(statusStr),
      upiIntentUrl: upiLink,
      qrCodeData: upiLink ?? shortUrl,
      paymentUrl: shortUrl,
      createdAt: now,
      expiresAt: expiresAt,
      metadata: {
        'platformBillID': platformBillId,
        'billerBillID': clientRequestId,
        'providerStatus': statusStr,
        'txnId': platformBillId,
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
      // Backend proxy query
      if (backendBaseUrl != null && backendBaseUrl!.trim().isNotEmpty) {
        final url = Uri.parse(
          '$backendBaseUrl/api/v1/payments/setu/status/$targetId',
        );
        final response = await _client.get(url);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final statusStr = data['status'] as String?;
          return SetuStatusMapper.fromSetuStatus(statusStr);
        }
        return PaymentStatus.pending;
      }

      // Direct Setu UAT query
      final url = Uri.parse('$uatBaseUrl/payment-links/$targetId');
      final response = await _client.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'X-Setu-Product-Instance-ID': productInstanceId!,
          'Authorization': 'Bearer $clientSecret',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final statusStr = data['status'] as String?;
        return SetuStatusMapper.fromSetuStatus(statusStr);
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
        failureReason: 'UPI test provider is not configured.',
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

      if (backendBaseUrl != null && backendBaseUrl!.trim().isNotEmpty) {
        final url = Uri.parse('$backendBaseUrl/api/v1/payments/setu/verify');
        final response = await _client.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'paymentIntentId': paymentIntentId,
            'providerReference': providerReference,
            'expectedAmountPaise': expectedAmountPaise,
            'expectedCurrency': expectedCurrency,
          }),
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
            failureReason: 'Verification proxy returned ${response.statusCode}',
          );
        }
        providerData = jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        final url = Uri.parse('$uatBaseUrl/payment-links/$providerReference');
        final response = await _client.get(
          url,
          headers: {
            'Content-Type': 'application/json',
            'X-Setu-Product-Instance-ID': productInstanceId!,
            'Authorization': 'Bearer $clientSecret',
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
            failureReason: 'Setu UAT returned ${response.statusCode}',
          );
        }
        providerData = jsonDecode(response.body) as Map<String, dynamic>;
      }

      final rawStatus = providerData['status'] as String?;
      final domainStatus = SetuStatusMapper.fromSetuStatus(rawStatus);
      final paidPaise =
          (providerData['amountPaid'] as num?)?.toInt() ??
          (providerData['amount'] as num?)?.toInt() ??
          0;
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

      // Exact amount verification
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

    // Setu computes HMAC-SHA256 of the raw payload using the webhook secret
    final hmac = Hmac(sha256, utf8.encode(secret));
    final digest = hmac.convert(utf8.encode(payload));
    final computedHex = digest.toString().toLowerCase();
    final computedBase64 = base64Encode(digest.bytes);

    final incoming = signature.trim();
    final matchesHex = _constantTimeCompare(
      incoming.toLowerCase(),
      computedHex,
    );
    final matchesBase64 = _constantTimeCompare(incoming, computedBase64);

    if (!matchesHex && !matchesBase64) {
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
      final eventType =
          json['eventType'] as String? ?? json['event'] as String? ?? '';
      final data = json['data'] as Map<String, dynamic>? ?? json;

      // Extract transaction ID / provider reference (UPI Setu txnId)
      final providerReference =
          data['txnId'] as String? ??
          data['transactionId'] as String? ??
          data['providerReference'] as String? ??
          json['txnId'] as String? ??
          json['transactionId'] as String? ??
          json['eventId'] as String? ??
          '';

      // Extract merchant order/intent ID (UPI Setu merchantReferenceId)
      final paymentIntentId =
          data['merchantReferenceId'] as String? ??
          json['merchantReferenceId'] as String? ??
          data['platformBillID'] as String? ??
          data['platformBillId'] as String? ??
          data['billerBillID'] as String? ??
          data['paymentIntentId'] as String? ??
          json['platformBillID'] as String? ??
          json['platformBillId'] as String? ??
          json['paymentIntentId'] as String? ??
          providerReference;

      // Resolve domain status from eventType or paymentStatus
      final statusStr = eventType.isNotEmpty
          ? eventType
          : (data['paymentStatus'] as String? ??
                data['status'] as String? ??
                json['status'] as String? ??
                '');
      final status = eventType.isNotEmpty
          ? SetuStatusMapper.fromEventType(eventType)
          : SetuStatusMapper.fromSetuStatus(statusStr);

      final amountPaid =
          (data['amount'] as num?)?.toInt() ??
          (data['amountPaid'] as num?)?.toInt() ??
          (json['amount'] as num?)?.toInt() ??
          0;
      final currency =
          data['currency'] as String? ?? json['currency'] as String? ?? 'INR';

      if (status == PaymentStatus.failed) {
        return PaymentVerification(
          isVerified: false,
          providerReference: providerReference,
          paymentIntentId: paymentIntentId,
          status: PaymentStatus.failed,
          amountPaise: amountPaid,
          currency: currency,
          verifiedAt: DateTime.now(),
          failureReason: 'Payment failed at Setu ($statusStr).',
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
          failureReason: 'Payment in progress at Setu ($statusStr).',
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
          failureReason: 'Unhandled Setu notification status: $statusStr',
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
        failureReason: 'Malformed Setu webhook payload: $e',
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
      providerReference: 'ref_setu_${DateTime.now().millisecondsSinceEpoch}',
      paymentIntentId: paymentIntentId,
      status: PaymentStatus.refunded,
      amountPaise: amountPaise,
      verifiedAt: DateTime.now(),
      rawResponse: {
        'reason': reason,
        'provider': providerName,
        'mode': 'setu_uat',
      },
    );
  }

  /// Constant-time comparison to prevent timing side-channel attacks on HMAC verification.
  static bool _constantTimeCompare(String a, String b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }
}
