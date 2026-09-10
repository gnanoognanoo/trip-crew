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

  static Future<void> logAccountCreated() => logEvent('account_created');
  static Future<void> logTripCreated(String tripId, String tripType) =>
      logEvent('trip_created', {'trip_id': tripId, 'trip_type': tripType});
  static Future<void> logTripJoined(String tripId) =>
      logEvent('trip_joined', {'trip_id': tripId});
  static Future<void> logInviteShared(String tripId) =>
      logEvent('invite_shared', {'trip_id': tripId});
  static Future<void> logCrewActivated(String tripId, int memberCount) =>
      logEvent('crew_activated', {'trip_id': tripId, 'members': memberCount});
  static Future<void> logExpenseAdded(String tripId, double amount) =>
      logEvent('expense_added', {'trip_id': tripId, 'amount': amount});
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
}
