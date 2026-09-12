import 'dart:developer' as developer;
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:tripcrew/core/services/firebase_service.dart';

/// Firebase Analytics service tracking core startup metrics without capturing sensitive data.
class AnalyticsService {
  static FirebaseAnalytics? get _analytics =>
      FirebaseService.isInitialized ? FirebaseAnalytics.instance : null;

  static Future<void> logEvent(
    String name, [
    Map<String, Object>? parameters,
  ]) async {
    developer.log(
      'Analytics Event: $name, Params: $parameters',
      name: 'AnalyticsService',
    );
    try {
      await _analytics?.logEvent(name: name, parameters: parameters);
    } catch (_) {}
  }

  static Future<void> logSignUp() => logEvent('sign_up');
  static Future<void> logLogin() => logEvent('login');
  static Future<void> logAccountCreated() => logSignUp();
  static Future<void> logTripCreated(String tripId, String tripType) =>
      logEvent('trip_created', {'trip_id': tripId, 'trip_type': tripType});
  static Future<void> logTripJoined(String tripId) =>
      logEvent('trip_joined', {'trip_id': tripId});
  static Future<void> logInviteShared(String tripId) =>
      logEvent('invite_shared', {'trip_id': tripId});
  static Future<void> logCrewActivated(String tripId, int memberCount) =>
      logEvent('crew_activated', {'trip_id': tripId, 'members': memberCount});
  static Future<void> logExpenseAdded(
    String tripId, {
    String? category,
    String? paymentSource,
  }) {
    final params = <String, Object>{'trip_id': tripId};
    if (category != null) params['category'] = category;
    if (paymentSource != null) params['payment_source'] = paymentSource;
    return logEvent('expense_added', params);
  }

  static Future<void> logItineraryItemAdded(String tripId) =>
      logEvent('itinerary_item_added', {'trip_id': tripId});
  static Future<void> logChecklistItemCompleted(String tripId) =>
      logEvent('checklist_item_completed', {'trip_id': tripId});
  static Future<void> logMemoryUploaded(String tripId) =>
      logEvent('memory_uploaded', {'trip_id': tripId});
  static Future<void> logPulseSent(String tripId, String pulseType) =>
      logEvent('pulse_sent', {'trip_id': tripId, 'pulse_type': pulseType});
  static Future<void> logTripCompleted(String tripId) =>
      logEvent('trip_completed', {'trip_id': tripId});
  static Future<void> logRecapViewed(String tripId) =>
      logEvent('recap_viewed', {'trip_id': tripId});

  // TripCrew Pay Sandbox Analytics (Strict privacy: NO amounts, descriptions, merchants, or user names)
  static Future<void> logTripPayOpened(String tripId) =>
      logEvent('trip_pay_opened', {'trip_id': tripId});
  static Future<void> logTripPotContributionStarted(String tripId) =>
      logEvent('trip_pot_contribution_started', {'trip_id': tripId});
  static Future<void> logTripPotContributionCompleted(String tripId) =>
      logEvent('trip_pot_contribution_completed', {'trip_id': tripId});
  static Future<void> logTripPotPaymentStarted(String tripId) =>
      logEvent('trip_pot_payment_started', {'trip_id': tripId});
  static Future<void> logTripPotPaymentCompleted(String tripId) =>
      logEvent('trip_pot_payment_completed', {'trip_id': tripId});
  static Future<void> logTransactionHistoryOpened(String tripId) =>
      logEvent('transaction_history_opened', {'trip_id': tripId});
  static Future<void> logInsufficientBalanceShown(String tripId) =>
      logEvent('insufficient_balance_shown', {'trip_id': tripId});
}
