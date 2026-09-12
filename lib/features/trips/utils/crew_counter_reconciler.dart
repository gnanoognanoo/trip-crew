import 'package:cloud_firestore/cloud_firestore.dart';

/// Diagnostic reconciliation result representing the consistency
/// between the denormalized trip `memberCount` and actual member documents.
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
///
/// NOTE: Not used for high-frequency production queries.
/// Intended for test verification, administrative diagnostics, and maintenance audits.
class CrewCounterReconciler {
  CrewCounterReconciler._();

  /// Compares recorded Firestore trip `memberCount` with the actual
  /// count of documents in the `trips/{tripId}/members` subcollection.
  static Future<CrewReconciliationResult> reconcile({
    required FirebaseFirestore firestore,
    required String tripId,
  }) async {
    final tripDoc = await firestore.collection('trips').doc(tripId).get();
    if (!tripDoc.exists || tripDoc.data() == null) {
      throw Exception('Trip $tripId not found.');
    }

    final recorded = (tripDoc.data()!['memberCount'] as num?)?.toInt() ?? 0;
    final membersSnap = await firestore
        .collection('trips')
        .doc(tripId)
        .collection('members')
        .get();
    final actual = membersSnap.docs.length;
    final uids = membersSnap.docs.map((d) => d.id).toList();

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
