/// Canonical payment status for TripCrew Pay contributions and transactions.
enum PaymentStatus {
  created,
  pending,
  verifying,
  authorized,
  success,
  failed,
  expired,
  refunded;

  static PaymentStatus fromString(String val) {
    return PaymentStatus.values.firstWhere(
      (e) => e.name.toLowerCase() == val.toLowerCase(),
      orElse: () => PaymentStatus.pending,
    );
  }
}

/// Supported payment instrument types.
/// Note: RuPay and partner cards are defined as interface specifications
/// for future RBI-authorized PPI partnerships; no card numbers or credentials
/// are collected or stored in the client.
enum PaymentInstrumentType {
  upi,
  rupayPrepaid,
  partnerCard,
  unknown;

  static PaymentInstrumentType fromString(String val) {
    return PaymentInstrumentType.values.firstWhere(
      (e) => e.name.toLowerCase() == val.toLowerCase(),
      orElse: () => PaymentInstrumentType.unknown,
    );
  }
}
