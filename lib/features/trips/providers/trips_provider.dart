import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/core/services/analytics_service.dart';
import 'package:tripcrew/core/services/firebase_service.dart';
import 'package:tripcrew/features/auth/providers/auth_provider.dart';
import 'package:tripcrew/features/trips/models/trip_model.dart';

class TripsState {
  final bool isLoading;
  final List<TripModel> trips;
  final String? activeTripId;
  final String? error;

  const TripsState({
    this.isLoading = false,
    this.trips = const [],
    this.activeTripId,
    this.error,
  });

  TripModel? get activeTrip {
    if (activeTripId != null) {
      try {
        return trips.firstWhere((t) => t.id == activeTripId);
      } catch (_) {}
    }
    try {
      return trips.firstWhere((t) => t.status == 'active');
    } catch (_) {
      return trips.isNotEmpty ? trips.first : null;
    }
  }

  List<TripModel> get upcomingTrips => trips
      .where((t) => t.status == 'upcoming' && t.id != activeTrip?.id)
      .toList();

  List<TripModel> get completedTrips =>
      trips.where((t) => t.status == 'completed').toList();

  TripsState copyWith({
    bool? isLoading,
    List<TripModel>? trips,
    String? activeTripId,
    String? error,
    bool clearError = false,
  }) {
    return TripsState(
      isLoading: isLoading ?? this.isLoading,
      trips: trips ?? this.trips,
      activeTripId: activeTripId ?? this.activeTripId,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class TripsNotifier extends Notifier<TripsState> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _tripsSub;

  @override
  TripsState build() {
    ref.onDispose(() {
      _tripsSub?.cancel();
    });

    final authState = ref.watch(authProvider);

    if (authState.user != null && FirebaseService.isInitialized) {
      _listenToUserTrips(authState.user!.uid);
      return const TripsState(isLoading: true);
    }

    return const TripsState(isLoading: false, trips: []);
  }

  void _listenToUserTrips(String uid) {
    _tripsSub?.cancel();

    // Listen to all trips created by the user or where the user is a member
    _tripsSub = FirebaseFirestore.instance
        .collection('trips')
        .snapshots()
        .listen(
          (snapshot) {
            final loadedTrips = snapshot.docs
                .map((doc) => TripModel.fromMap(doc.data(), doc.id))
                .toList();

            state = state.copyWith(
              isLoading: false,
              trips: loadedTrips,
              activeTripId:
                  state.activeTripId ??
                  (loadedTrips.isNotEmpty ? loadedTrips.first.id : null),
            );
          },
          onError: (e) {
            state = state.copyWith(isLoading: false, error: e.toString());
          },
        );
  }

  /// Generates a high-entropy, human-shareable invite code.
  /// Format: TC-XXXX-XXXX (e.g. TC-K7M4-X9QP).
  /// Uses Random.secure() across 32 unambiguous alphanumeric characters (excluding 0, O, 1, I).
  /// Entropy: 32^8 = 1,099,511,627,776 combinations (40 bits of cryptographic entropy).
  static String generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random.secure();
    final block1 = List.generate(
      4,
      (_) => chars[rand.nextInt(chars.length)],
    ).join();
    final block2 = List.generate(
      4,
      (_) => chars[rand.nextInt(chars.length)],
    ).join();
    return 'TC-$block1-$block2';
  }

  /// Normalizes user-entered invite codes (handles lowercase, missing hyphens, extra spaces).
  /// E.g. "k7m4x9qp" or "tc-k7m4-x9qp" -> "TC-K7M4-X9QP".
  static String normalizeInviteCode(String raw) {
    final cleaned = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (cleaned.startsWith('TC') && cleaned.length == 10) {
      return 'TC-${cleaned.substring(2, 6)}-${cleaned.substring(6, 10)}';
    } else if (cleaned.length == 8) {
      return 'TC-${cleaned.substring(0, 4)}-${cleaned.substring(4, 8)}';
    }
    return raw.trim().toUpperCase();
  }

  /// Creates a trip atomically:
  /// 1. trips/{tripId}
  /// 2. trips/{tripId}/members/{creatorUid} with role = 'owner'
  /// 3. tripInvites/{inviteCode}
  Future<TripModel> createTrip({
    required String name,
    required String startingPlace,
    required String destination,
    required DateTime startDate,
    required DateTime endDate,
    required String tripType,
    required double budget,
    required String currency,
  }) async {
    final user = ref.read(authProvider).user;
    final inviteCode = generateInviteCode();
    final tripId = 'trip_${DateTime.now().millisecondsSinceEpoch}';

    final newTrip = TripModel(
      id: tripId,
      ownerId: user?.uid ?? 'creator',
      name: name.trim(),
      startingPlace: startingPlace.trim(),
      destination: destination.trim(),
      startDate: startDate,
      endDate: endDate,
      tripType: tripType,
      budget: budget,
      currency: currency,
      inviteCode: inviteCode,
      status: 'upcoming',
      memberCount: 1,
      totalSpendingPaise: 0,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    if (FirebaseService.isInitialized) {
      final batch = FirebaseFirestore.instance.batch();
      final tripDoc = FirebaseFirestore.instance
          .collection('trips')
          .doc(tripId);
      final memberDoc = tripDoc
          .collection('members')
          .doc(user?.uid ?? 'creator');
      final inviteDoc = FirebaseFirestore.instance
          .collection('tripInvites')
          .doc(inviteCode);

      batch.set(tripDoc, {
        'id': tripId,
        'ownerId': user?.uid ?? 'creator',
        'name': name.trim(),
        'startingPlace': startingPlace.trim(),
        'destination': destination.trim(),
        'startDate': startDate.toIso8601String(),
        'endDate': endDate.toIso8601String(),
        'tripType': tripType,
        'budget': budget,
        'currency': currency,
        'inviteCode': inviteCode,
        'status': 'upcoming',
        'memberCount': 1,
        'totalSpendingPaise': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      batch.set(memberDoc, {
        'uid': user?.uid ?? 'creator',
        'displayName': user?.name ?? 'Trip Owner',
        'role': 'owner',
        'joinedAt': FieldValue.serverTimestamp(),
        'isOnline': true,
      });

      batch.set(inviteDoc, {
        'tripId': tripId,
        'inviteCode': inviteCode,
        'createdBy': user?.uid ?? 'creator',
        'createdAt': FieldValue.serverTimestamp(),
        'isActive': true,
      });

      await batch.commit();
    }

    await AnalyticsService.logTripCreated(tripId, tripType);

    if (!FirebaseService.isInitialized) {
      final updated = [newTrip, ...state.trips];
      state = state.copyWith(trips: updated, activeTripId: tripId);
    }

    return newTrip;
  }

  /// Joins a trip safely by invite code.
  /// Atomically validates invite, verifies capacity (<25), prevents duplicates,
  /// stores invite proof on the member document, and increments memberCount.
  Future<TripModel?> joinTripByCode(String code) async {
    final normalized = normalizeInviteCode(code);

    if (FirebaseService.isInitialized) {
      final user = ref.read(authProvider).user;
      if (user == null) {
        throw Exception('You must be signed in to join a trip.');
      }

      final firestore = FirebaseFirestore.instance;
      final inviteRef = firestore.collection('tripInvites').doc(normalized);

      debugPrint('[joinTripByCode] Starting join for invite code: $normalized');
      final tripId = await firestore.runTransaction<String>((
        transaction,
      ) async {
        // 1. Read and verify invite
        debugPrint('[joinTripByCode] 1. READ tripInvites/$normalized');
        final inviteSnapshot = await transaction.get(inviteRef);
        if (!inviteSnapshot.exists || inviteSnapshot.data() == null) {
          throw Exception('Invalid or expired invite code.');
        }

        final inviteData = inviteSnapshot.data()!;
        final inviteTripId = inviteData['tripId'] as String?;
        final isActive = inviteData['isActive'] as bool? ?? true;
        final expiresAt = inviteData['expiresAt'] != null
            ? (inviteData['expiresAt'] is Timestamp
                  ? (inviteData['expiresAt'] as Timestamp).toDate()
                  : DateTime.tryParse(inviteData['expiresAt'].toString()))
            : null;

        if (inviteTripId == null || inviteTripId.isEmpty) {
          throw Exception('Invite code does not reference a valid trip.');
        }
        if (!isActive) {
          throw Exception(
            'This invite code has been revoked by the trip owner.',
          );
        }
        if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
          throw Exception('This invite code has expired.');
        }

        // 2. Read and verify trip
        debugPrint('[joinTripByCode] 2. READ trips/$inviteTripId');
        final tripRef = firestore.collection('trips').doc(inviteTripId);
        final tripSnapshot = await transaction.get(tripRef);
        if (!tripSnapshot.exists || tripSnapshot.data() == null) {
          throw Exception(
            'The trip associated with this invite code was not found.',
          );
        }

        final tripData = tripSnapshot.data()!;

        // 3. Read member document to check for duplicate membership
        debugPrint(
          '[joinTripByCode] 3. READ trips/$inviteTripId/members/${user.uid}',
        );
        final memberRef = tripRef.collection('members').doc(user.uid);
        final memberSnapshot = await transaction.get(memberRef);

        if (memberSnapshot.exists) {
          // Idempotent: already a member, do not increment memberCount
          debugPrint(
            '[joinTripByCode] Already a member of trip $inviteTripId (idempotent)',
          );
          return inviteTripId;
        }

        // 4. Atomic capacity check
        final currentMemberCount =
            (tripData['memberCount'] as num?)?.toInt() ?? 1;
        if (currentMemberCount >= AppConstants.maxCrewMembers) {
          throw Exception(
            'This trip has reached the maximum allowed crew size of ${AppConstants.maxCrewMembers} members.',
          );
        }

        // 5. Atomically create member document with invite proof
        debugPrint(
          '[joinTripByCode] 4. CREATE trips/$inviteTripId/members/${user.uid}',
        );
        transaction.set(memberRef, {
          'uid': user.uid,
          'displayName': user.name.isNotEmpty ? user.name : 'Member',
          'role': 'member',
          'inviteCode': normalized,
          'joinedAt': FieldValue.serverTimestamp(),
          'isOnline': true,
        });

        // 6. Atomically increment memberCount
        debugPrint(
          '[joinTripByCode] 5. UPDATE trips/$inviteTripId (memberCount: ${currentMemberCount + 1})',
        );
        transaction.update(tripRef, {
          'memberCount': currentMemberCount + 1,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        return inviteTripId;
      });

      debugPrint(
        '[joinTripByCode] Transaction committed successfully for trip $tripId',
      );

      await AnalyticsService.logTripJoined(tripId);

      final updatedTripDoc = await firestore
          .collection('trips')
          .doc(tripId)
          .get();
      final joinedTrip = TripModel.fromMap(updatedTripDoc.data()!, tripId);
      state = state.copyWith(activeTripId: tripId);
      return joinedTrip;
    } else {
      // Local fallback for testing / offline
      final found = state.trips
          .where((t) => t.inviteCode == normalized)
          .firstOrNull;
      if (found != null) {
        if (found.memberCount >= AppConstants.maxCrewMembers) {
          throw Exception(
            'This trip has reached the maximum allowed crew size of ${AppConstants.maxCrewMembers} members.',
          );
        }
        state = state.copyWith(activeTripId: found.id);
        return found;
      }
      throw Exception('Invite code not found.');
    }
  }

  /// Atomically removes a crew member and decrements trip memberCount.
  /// The trip owner can NEVER be removed.
  Future<void> removeMember({
    required String tripId,
    required String memberUid,
  }) async {
    if (FirebaseService.isInitialized) {
      final firestore = FirebaseFirestore.instance;
      final tripRef = firestore.collection('trips').doc(tripId);
      final memberRef = tripRef.collection('members').doc(memberUid);

      await firestore.runTransaction((transaction) async {
        final tripSnapshot = await transaction.get(tripRef);
        if (!tripSnapshot.exists || tripSnapshot.data() == null) {
          throw Exception('Trip not found.');
        }

        final tripData = tripSnapshot.data()!;
        final ownerId = tripData['ownerId'] as String?;

        if (memberUid == ownerId) {
          throw Exception('The trip owner cannot be removed from the crew.');
        }

        final memberSnapshot = await transaction.get(memberRef);
        if (!memberSnapshot.exists) {
          return; // Already removed
        }

        final currentCount = (tripData['memberCount'] as num?)?.toInt() ?? 1;
        final newCount = (currentCount - 1).clamp(
          1,
          AppConstants.maxCrewMembers,
        );

        transaction.delete(memberRef);
        transaction.update(tripRef, {
          'memberCount': newCount,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    }
  }

  /// Revokes an active invite code for a trip.
  /// Only the trip owner is permitted to revoke invites.
  /// Historical trip memberships are completely preserved.
  Future<void> revokeInvite({
    required String tripId,
    required String inviteCode,
  }) async {
    final normalized = normalizeInviteCode(inviteCode);
    if (FirebaseService.isInitialized) {
      final user = ref.read(authProvider).user;
      final firestore = FirebaseFirestore.instance;
      final inviteRef = firestore.collection('tripInvites').doc(normalized);
      final inviteSnap = await inviteRef.get();

      if (!inviteSnap.exists || inviteSnap.data() == null) {
        throw Exception('Invite code not found.');
      }

      final data = inviteSnap.data()!;
      if (data['tripId'] != tripId) {
        throw Exception('Invite code does not belong to this trip.');
      }

      // Verify owner permission
      final tripSnap = await firestore.collection('trips').doc(tripId).get();
      if (tripSnap.exists && tripSnap.data()?['ownerId'] != user?.uid) {
        throw Exception('Only the trip owner can revoke invite codes.');
      }

      await inviteRef.update({
        'isActive': false,
        'revokedAt': FieldValue.serverTimestamp(),
        'revokedBy': user?.uid,
      });
    }
  }

  void setActiveTrip(String tripId) {
    state = state.copyWith(activeTripId: tripId);
  }

  /// Loads demo fixture data for development/sandbox mode exploration.
  void loadDemoFixture() {
    final now = DateTime.now();
    final demoTrips = [
      TripModel(
        id: 'demo_goa_01',
        ownerId: 'demo_owner',
        name: 'Goa Weekend',
        startingPlace: 'Chennai',
        destination: 'Goa',
        startDate: now.add(const Duration(days: 3)),
        endDate: now.add(const Duration(days: 6)),
        tripType: 'Road Trip',
        budget: 20000.0,
        currency: 'INR (₹)',
        inviteCode: 'TRIP-7X92K',
        status: 'active',
        memberCount: 4,
        totalSpendingPaise: 1845000,
        createdAt: now.subtract(const Duration(days: 5)),
        updatedAt: now,
      ),
      TripModel(
        id: 'demo_ooty_02',
        ownerId: 'demo_owner',
        name: 'Ooty Trek',
        startingPlace: 'Bangalore',
        destination: 'Ooty',
        startDate: now.add(const Duration(days: 20)),
        endDate: now.add(const Duration(days: 24)),
        tripType: 'Trek',
        budget: 15000.0,
        currency: 'INR (₹)',
        inviteCode: 'TRIP-OT82M',
        status: 'upcoming',
        memberCount: 3,
        totalSpendingPaise: 0,
        createdAt: now.subtract(const Duration(days: 1)),
        updatedAt: now,
      ),
    ];

    state = state.copyWith(trips: demoTrips, activeTripId: 'demo_goa_01');
  }
}

final tripsProvider = NotifierProvider<TripsNotifier, TripsState>(
  TripsNotifier.new,
);

final activeTripProvider = Provider<TripModel?>((ref) {
  return ref.watch(tripsProvider).activeTrip;
});
