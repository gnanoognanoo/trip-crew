import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tripcrew/features/trip_pay/models/payment_status.dart';
import 'package:tripcrew/features/trip_pay/providers/razorpay_provider.dart';
import 'package:tripcrew/features/trip_pay/providers/sandbox_payment_provider.dart';

void main() {
  group('PART 7 — PAYMENT ATTEMPT LOOKUP & IDEMPOTENCY UNIT TESTS', () {
    test('PaymentIntent metadata carries both paymentAttemptId and orderId', () async {
      final provider = SandboxPaymentProvider();
      final intent = await provider.createContributionIntent(
        tripId: 'trip_test_1',
        uid: 'user_test_1',
        amountPaise: 10000, // ₹100
        clientRequestId: 'cr_test_100',
        metadata: {
          'paymentAttemptId': 'att_TEST_123',
          'payment_attempt_id': 'att_TEST_123',
        },
      );

      expect(intent.id, isNotEmpty);
      expect(intent.metadata['paymentAttemptId'], 'att_TEST_123');
      expect(intent.metadata['payment_attempt_id'], 'att_TEST_123');
    });

    test('RazorpayProvider.verifyPayment passes both paymentAttemptId and razorpayOrderId in request payload', () async {
      String? capturedBody;

      // Mock HTTP client that captures request payload
      final provider = RazorpayPaymentProvider(
        verificationUrl: 'https://example.supabase.co/functions/v1/razorpay-verify',
        keyId: 'rzp_test_key',
        keySecret: 'rzp_test_secret',
        httpClient: MockHttpClient((request) async {
          capturedBody = request.body;
          return MockHttpResponse(
            statusCode: 200,
            body: jsonEncode({
              'isVerified': true,
              'status': 'success',
              'amountPaid': 10100,
              'currency': 'INR',
              'transactionId': 'tx_TEST_999',
              'rpcDetails': {
                'success': true,
                'attempt_id': 'att_TEST_123',
                'transaction_id': 'tx_TEST_999',
                'balance_after': 10100,
              },
            }),
          );
        }),
      );

      final verification = await provider.verifyPayment(
        paymentIntentId: 'order_TEST_456',
        providerReference: 'pay_TEST_789|simulated_sig|order_TEST_456',
        expectedAmountPaise: 10100,
        expectedCurrency: 'INR',
        tripId: 'trip_TEST_1',
        initiatedByName: 'Tester',
        paymentAttemptId: 'att_TEST_123',
      );

      expect(verification.isVerified, isTrue);
      expect(verification.status, PaymentStatus.success);
      expect(capturedBody, isNotNull);

      final decoded = jsonDecode(capturedBody!) as Map<String, dynamic>;
      expect(decoded['paymentAttemptId'], 'att_TEST_123');
      expect(decoded['payment_attempt_id'], 'att_TEST_123');
      expect(decoded['razorpayOrderId'], 'order_TEST_456');
      expect(decoded['razorpay_order_id'], 'order_TEST_456');
      expect(decoded['razorpayPaymentId'], 'pay_TEST_789');
    });

    test('Verification failure on non-existent attempt returns controlled failure and does not claim success', () async {
      final provider = RazorpayPaymentProvider(
        verificationUrl: 'https://example.supabase.co/functions/v1/razorpay-verify',
        keyId: 'rzp_test_key',
        keySecret: 'rzp_test_secret',
        httpClient: MockHttpClient((request) async {
          return MockHttpResponse(
            statusCode: 400,
            body: jsonEncode({
              'isVerified': false,
              'status': 'failed',
              'failureReason': 'PAYMENT_ATTEMPT_NOT_FOUND: No matching payment attempt was found for finalization',
              'rpcDetails': {
                'success': false,
                'error': 'PAYMENT_ATTEMPT_NOT_FOUND',
                'message': 'No matching payment attempt was found for finalization',
              },
            }),
          );
        }),
      );

      final verification = await provider.verifyPayment(
        paymentIntentId: 'order_NONEXISTENT',
        providerReference: 'pay_NONEXISTENT|simulated_sig|order_NONEXISTENT',
        expectedAmountPaise: 10100,
        expectedCurrency: 'INR',
        tripId: 'trip_TEST_1',
        initiatedByName: 'Tester',
        paymentAttemptId: 'nonexistent_att',
      );

      expect(verification.isVerified, isFalse);
      expect(verification.status, PaymentStatus.failed);
      expect(verification.failureReason, contains('PAYMENT_ATTEMPT_NOT_FOUND'));
    });

    test('Second verification of already finalized attempt returns idempotent success without throwing error', () async {
      int callCount = 0;
      final provider = RazorpayPaymentProvider(
        verificationUrl: 'https://example.supabase.co/functions/v1/razorpay-verify',
        keyId: 'rzp_test_key',
        keySecret: 'rzp_test_secret',
        httpClient: MockHttpClient((request) async {
          callCount++;
          return MockHttpResponse(
            statusCode: 200,
            body: jsonEncode({
              'isVerified': true,
              'status': 'success',
              'amountPaid': 10100,
              'currency': 'INR',
              'transactionId': 'tx_EXISTING_123',
              'rpcDetails': {
                'success': true,
                'idempotent': true,
                'message': 'Payment attempt already finalized',
                'attempt_id': 'att_TEST_123',
                'transaction_id': 'tx_EXISTING_123',
              },
            }),
          );
        }),
      );

      // Call 1
      final v1 = await provider.verifyPayment(
        paymentIntentId: 'order_TEST_456',
        providerReference: 'pay_TEST_789|simulated_sig|order_TEST_456',
        expectedAmountPaise: 10100,
        paymentAttemptId: 'att_TEST_123',
      );
      expect(v1.isVerified, isTrue);

      // Call 2 (idempotent retry)
      final v2 = await provider.verifyPayment(
        paymentIntentId: 'order_TEST_456',
        providerReference: 'pay_TEST_789|simulated_sig|order_TEST_456',
        expectedAmountPaise: 10100,
        paymentAttemptId: 'att_TEST_123',
      );

      expect(v2.isVerified, isTrue);
      expect(v2.status, PaymentStatus.success);
      expect(callCount, 2);
    });
  });
}

// Simple Mock HTTP Client & Response for unit tests
class MockHttpResponse {
  final int statusCode;
  final String body;
  MockHttpResponse({required this.statusCode, required this.body});
}

class MockHttpClient implements http.Client {
  final Future<MockHttpResponse> Function(http.Request request) handler;
  MockHttpClient(this.handler);

  @override
  Future<http.Response> post(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
    final req = http.Request('POST', url);
    if (headers != null) req.headers.addAll(headers);
    if (body != null) {
      if (body is String) {
        req.body = body;
      } else if (body is List<int>) {
        req.bodyBytes = body;
      } else if (body is Map) {
        req.bodyFields = body.cast<String, String>();
      }
    }
    final res = await handler(req);
    return http.Response(res.body, res.statusCode, headers: {'content-type': 'application/json'});
  }

  @override
  void close() {}

  @override
  Future<http.Response> delete(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) => throw UnimplementedError();
  @override
  Future<http.Response> get(Uri url, {Map<String, String>? headers}) => throw UnimplementedError();
  @override
  Future<http.Response> head(Uri url, {Map<String, String>? headers}) => throw UnimplementedError();
  @override
  Future<http.Response> patch(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) => throw UnimplementedError();
  @override
  Future<http.Response> put(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) => throw UnimplementedError();
  @override
  Future<String> read(Uri url, {Map<String, String>? headers}) => throw UnimplementedError();
  @override
  Future<Uint8List> readBytes(Uri url, {Map<String, String>? headers}) => throw UnimplementedError();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => throw UnimplementedError();
}
