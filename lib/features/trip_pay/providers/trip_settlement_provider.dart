import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tripcrew/features/trip_pay/services/trip_settlement_service.dart';

/// Provider for the TripSettlementService instance.
final tripSettlementServiceProvider = Provider<TripSettlementService>((ref) {
  return TripSettlementService();
});
