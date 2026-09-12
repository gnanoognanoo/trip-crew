import 'package:tripcrew/features/trip_pay/models/payment_status.dart';

/// External provider transaction record metadata.
class ProviderTransaction {
  final String id;
  final String provider;
  final String providerReference;
  final int amountPaise;
  final PaymentStatus status;
  final PaymentInstrumentType instrumentType;
  final DateTime timestamp;
  final Map<String, dynamic> rawDetails;

  const ProviderTransaction({
    required this.id,
    required this.provider,
    required this.providerReference,
    required this.amountPaise,
    required this.status,
    this.instrumentType = PaymentInstrumentType.upi,
    required this.timestamp,
    this.rawDetails = const {},
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'provider': provider,
    'providerReference': providerReference,
    'amountPaise': amountPaise,
    'status': status.name,
    'instrumentType': instrumentType.name,
    'timestamp': timestamp.toIso8601String(),
    'rawDetails': rawDetails,
  };
}
