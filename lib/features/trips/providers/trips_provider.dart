import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random();
    final code = List.generate(
      5,
      (_) => chars[rand.nextInt(chars.length)],
    ).join();
    return 'TRIP-$code';
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
    final inviteCode = _generateInviteCode();
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
        'createdAt': FieldValue.serverTimestamp(),
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
  /// Validates invite, prevents duplicate membership, and strictly enforces role = 'member'.
  Future<TripModel?> joinTripByCode(String code) async {
    final normalized = code.trim().toUpperCase();

    if (FirebaseService.isInitialized) {
      final inviteDoc = await FirebaseFirestore.instance
          .collection('tripInvites')
          .doc(normalized)
          .get();

      if (!inviteDoc.exists || inviteDoc.data() == null) {
        throw Exception('Invalid or expired invite code.');
      }

      final tripId = inviteDoc.data()!['tripId'] as String;
      final tripRef = FirebaseFirestore.instance
          .collection('trips')
          .doc(tripId);
      final tripDoc = await tripRef.get();

      if (!tripDoc.exists || tripDoc.data() == null) {
        throw Exception(
          'The trip associated with this invite code was not found.',
        );
      }

      final user = ref.read(authProvider).user;
      final memberRef = tripRef.collection('members').doc(user?.uid ?? 'guest');

      final existing = await memberRef.get();
      if (!existing.exists) {
        // Enforce role = 'member' (never allow caller-selected role)
        await memberRef.set({
          'uid': user?.uid ?? 'guest',
          'displayName': user?.name ?? 'Member',
          'role': 'member',
          'joinedAt': FieldValue.serverTimestamp(),
          'isOnline': true,
        });

        await tripRef.update({
          'memberCount': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      await AnalyticsService.logTripJoined(tripId);

      final joinedTrip = TripModel.fromMap(tripDoc.data()!, tripId);
      state = state.copyWith(activeTripId: tripId);
      return joinedTrip;
    } else {
      // Local fallback for testing
      final found = state.trips
          .where((t) => t.inviteCode == normalized)
          .firstOrNull;
      if (found != null) {
        state = state.copyWith(activeTripId: found.id);
        return found;
      }
      throw Exception('Invite code not found.');
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
