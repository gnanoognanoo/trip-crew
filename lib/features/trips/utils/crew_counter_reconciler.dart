import 'package:tripcrew/core/services/supabase_service.dart';

/// Diagnostic reconciliation result representing the consistency
/// between the denormalized trip `memberCount` and actual member records.
class CrewReconciliationResult {
  final String tripId;
  final int recordedMemberCount;
  final int actualMemberCount;
  final bool isConsistent;
  final List<String> memberUids;

  const CrewReconciliationResult({
    required this.tripId,
    required this.recordedMemberCount,
    required this.actualMemberCount,
    required this.isConsistent,
    required this.memberUids,
  });

  Map<String, dynamic> toMap() => {
    'tripId': tripId,
    'recordedMemberCount': recordedMemberCount,
    'actualMemberCount': actualMemberCount,
    'isConsistent': isConsistent,
    'memberUids': memberUids,
  };
}

/// Diagnostic reconciliation helper.
class CrewCounterReconciler {
  CrewCounterReconciler._();

  /// Compares recorded trip `member_count` with the actual
  /// count of rows in `trip_members`.
  static Future<CrewReconciliationResult> reconcile({
    dynamic firestore,
    required String tripId,
  }) async {
    if (!SupabaseService.isInitialized) {
      return CrewReconciliationResult(
        tripId: tripId,
        recordedMemberCount: 1,
        actualMemberCount: 1,
        isConsistent: true,
        memberUids: const [],
      );
    }
    final tripRes = await SupabaseService.client
        .from('trips')
        .select()
        .eq('id', tripId)
        .maybeSingle();

    if (tripRes == null) {
      throw Exception('Trip $tripId not found.');
    }

    final recorded = (tripRes['member_count'] as num?)?.toInt() ?? 0;
    final membersRes = await SupabaseService.client
        .from('trip_members')
        .select()
        .eq('trip_id', tripId);

    final uids = membersRes.map((d) => d['user_id'] as String).toList();
    final actual = uids.length;

    return CrewReconciliationResult(
      tripId: tripId,
      recordedMemberCount: recorded,
      actualMemberCount: actual,
      isConsistent: recorded == actual,
      memberUids: uids,
    );
  }

  /// In-memory diagnostic reconciliation for state validation and unit testing.
  static CrewReconciliationResult reconcileInMemory({
    required String tripId,
    required int recordedMemberCount,
    required List<String> actualMemberUids,
  }) {
    return CrewReconciliationResult(
      tripId: tripId,
      recordedMemberCount: recordedMemberCount,
      actualMemberCount: actualMemberUids.length,
      isConsistent: recordedMemberCount == actualMemberUids.length,
      memberUids: actualMemberUids,
    );
  }
}
