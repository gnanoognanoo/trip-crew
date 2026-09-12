import 'package:tripcrew/features/trip_pay/models/payment_status.dart';
import 'package:tripcrew/features/trip_pay/models/trip_pay_transaction.dart';
import 'package:tripcrew/features/trip_pay/providers/sandbox_trip_pay_provider.dart';

/// Abstract provider interface for Layer B (Shared Pot Spending).
///
/// Current implementation: [SandboxSharedPotProvider]
/// Future implementation: [RegulatedPpiSharedPotProvider]
///
/// CRITICAL ARCHITECTURAL BOUNDARY:
/// TripCrew Pay does NOT convert Firestore balances into real money.
/// Spending pooled money in the real world requires an RBI-authorized
/// bank / PPI partner capable of issuing prepaid virtual cards (e.g. RuPay)
/// or enabling merchant UPI out of an escrow/pooled account.
abstract class SharedPotProvider {
  String get providerName;
  bool get isRegulated;
  PaymentInstrumentType get supportedInstrument;

  /// Spends funds from the shared trip pot for an approved trip expense.
  Future<TripPayTransaction> spendFromPot({
    required String tripId,
    required int amountPaise,
    required String initiatedByUid,
    required String initiatedByName,
    required String description,
    required String category,
    String? merchantName,
    required String clientRequestId,
  });
}

/// Sandbox implementation of [SharedPotProvider].
/// Spends simulated sandbox money from the Trip Pot with atomic ledger updates.
class SandboxSharedPotProvider implements SharedPotProvider {
  final SandboxTripPayProvider _innerProvider;

  SandboxSharedPotProvider({SandboxTripPayProvider? innerProvider})
    : _innerProvider = innerProvider ?? SandboxTripPayProvider();

  @override
  String get providerName => 'sandbox_pot';

  @override
  bool get isRegulated => false;

  @override
  PaymentInstrumentType get supportedInstrument => PaymentInstrumentType.upi;

  @override
  Future<TripPayTransaction> spendFromPot({
    required String tripId,
    required int amountPaise,
    required String initiatedByUid,
    required String initiatedByName,
    required String description,
    required String category,
    String? merchantName,
    required String clientRequestId,
  }) {
    return _innerProvider.createPayment(
      tripId: tripId,
      amountPaise: amountPaise,
      initiatedByUid: initiatedByUid,
      initiatedByName: initiatedByName,
      description: description,
      category: category,
      merchantName: merchantName,
      clientRequestId: clientRequestId,
    );
  }
}

/// Interface specification for future RBI-authorized PPI / Banking Partner.
///
/// Future architecture supports:
/// - Virtual RuPay prepaid cards
/// - Partner-issued merchant payments
/// - Regulated escrow account debit
///
/// SAFETY: TripCrew never issues cards directly, never generates fake card
/// numbers, and never stores or prompts for CVV, card PIN, or OTP.
class RegulatedPpiSharedPotProvider implements SharedPotProvider {
  final String partnerName;
  final String? partnerPpiLicenseId;

  const RegulatedPpiSharedPotProvider({
    this.partnerName = 'RBI_AUTHORIZED_PPI_PARTNER',
    this.partnerPpiLicenseId,
  });

  @override
  String get providerName => 'regulated_ppi_$partnerName';

  @override
  bool get isRegulated => true;

  @override
  PaymentInstrumentType get supportedInstrument =>
      PaymentInstrumentType.rupayPrepaid;

  @override
  Future<TripPayTransaction> spendFromPot({
    required String tripId,
    required int amountPaise,
    required String initiatedByUid,
    required String initiatedByName,
    required String description,
    required String category,
    String? merchantName,
    required String clientRequestId,
  }) async {
    throw UnsupportedError(
      'Live real-money spending is not available without an active '
      'RBI-authorized PPI partner agreement and API credentials. '
      'TripCrew Pay is operating in Sandbox Mode.',
    );
  }
}
