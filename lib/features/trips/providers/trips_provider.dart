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

  List<TripModel> get upcomingTrips =>
      trips.where((t) => t.status == 'upcoming' && t.id != activeTrip?.id).toList();

  List<TripModel> get completedTrips =>
      trips.where((t) => t.status == 'completed').toList();

  TripsState copyWith({
    bool? isLoading,
    List<TripModel>? trips,
    String? activeTripId,
    String? error,
  }) {
    return TripsState(
      isLoading: isLoading ?? this.isLoading,
      trips: trips ?? this.trips,
      activeTripId: activeTripId ?? this.activeTripId,
      error: error,
    );
  }
}

class TripsNotifier extends Notifier<TripsState> {
  @override
  TripsState build() {
    final now = DateTime.now();
    final defaultTrips = [
      TripModel(
        id: 'trip_goa_01',
        ownerId: 'demo_kowshik_101',
        name: 'Goa Trip',
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
        totalSpendingPaise: 1845000, // ₹18,450
        createdAt: now.subtract(const Duration(days: 10)),
        updatedAt: now,
      ),
      TripModel(
        id: 'trip_ooty_02',
        ownerId: 'demo_kowshik_101',
        name: 'Ooty Trip',
        startingPlace: 'Bangalore',
        destination: 'Ooty',
        startDate: now.add(const Duration(days: 30)),
        endDate: now.add(const Duration(days: 33)),
        tripType: 'Vacation',
        budget: 15000.0,
        currency: 'INR (₹)',
        inviteCode: 'OOTY-82M',
        status: 'upcoming',
        memberCount: 3,
        totalSpendingPaise: 0,
        createdAt: now.subtract(const Duration(days: 2)),
        updatedAt: now,
      ),
    ];

    if (FirebaseService.isInitialized) {
      _loadTrips();
    }

    return TripsState(
      isLoading: false,
      trips: defaultTrips,
      activeTripId: 'trip_goa_01',
    );
  }

  void _loadTrips() {
    final user = ref.read(authProvider).user;
    if (user != null) {
      FirebaseFirestore.instance
          .collection('trips')
          .where('ownerId', isEqualTo: user.uid)
          .snapshots()
          .listen((snapshot) {
        final loadedTrips = snapshot.docs
            .map((doc) => TripModel.fromMap(doc.data(), doc.id))
            .toList();
        state = state.copyWith(isLoading: false, trips: loadedTrips);
      }, onError: (e) {
        state = state.copyWith(isLoading: false, error: e.toString());
      });
    }
  }

  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random();
    final code = List.generate(5, (_) => chars[rand.nextInt(chars.length)]).join();
    return 'TRIP-$code';
  }

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
      ownerId: user?.uid ?? 'guest_owner',
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
      final tripDoc = FirebaseFirestore.instance.collection('trips').doc(tripId);
      final memberDoc = tripDoc.collection('members').doc(user?.uid ?? 'guest');
      final inviteDoc = FirebaseFirestore.instance.collection('tripInvites').doc(inviteCode);

      batch.set(tripDoc, newTrip.toMap());
      batch.set(memberDoc, {
        'uid': user?.uid ?? 'guest',
        'displayName': user?.name ?? 'Trip Owner',
        'role': 'owner',
        'joinedAt': DateTime.now().toIso8601String(),
        'isOnline': true,
      });
      batch.set(inviteDoc, {
        'tripId': tripId,
        'inviteCode': inviteCode,
        'createdAt': DateTime.now().toIso8601String(),
      });

      await batch.commit();
    }

    await AnalyticsService.logTripCreated(tripId, tripType);

    final updated = [newTrip, ...state.trips];
    state = state.copyWith(trips: updated, activeTripId: tripId);
    return newTrip;
  }

  Future<TripModel?> joinTripByCode(String code) async {
    final normalized = code.trim().toUpperCase();

    if (FirebaseService.isInitialized) {
      final inviteDoc = await FirebaseFirestore.instance
          .collection('tripInvites')
          .doc(normalized)
          .get();

      if (!inviteDoc.exists || inviteDoc.data() == null) {
        throw Exception('Invalid invite code. Please check with your crew organizer.');
      }

      final tripId = inviteDoc.data()!['tripId'] as String;
      final tripDoc = await FirebaseFirestore.instance.collection('trips').doc(tripId).get();
      if (!tripDoc.exists || tripDoc.data() == null) {
        throw Exception('Trip associated with this code was not found.');
      }

      final user = ref.read(authProvider).user;
      final memberDoc = FirebaseFirestore.instance
          .collection('trips')
          .doc(tripId)
          .collection('members')
          .doc(user?.uid ?? 'guest');

      final existing = await memberDoc.get();
      if (!existing.exists) {
        await memberDoc.set({
          'uid': user?.uid ?? 'guest',
          'displayName': user?.name ?? 'Member',
          'role': 'member',
          'joinedAt': DateTime.now().toIso8601String(),
          'isOnline': true,
        });

        await FirebaseFirestore.instance.collection('trips').doc(tripId).update({
          'memberCount': FieldValue.increment(1),
        });
      }

      await AnalyticsService.logTripJoined(tripId);

      final joinedTrip = TripModel.fromMap(tripDoc.data()!, tripId);
      final list = [...state.trips.where((t) => t.id != tripId), joinedTrip];
      state = state.copyWith(trips: list, activeTripId: tripId);
      return joinedTrip;
    } else {
      // Local demo check
      final existingTrip = state.trips.firstWhere(
        (t) => t.inviteCode.toUpperCase() == normalized,
        orElse: () => TripModel(
          id: 'joined_${DateTime.now().millisecondsSinceEpoch}',
          ownerId: 'arun_owner',
          name: 'Manali Expedition',
          startingPlace: 'Delhi',
          destination: 'Manali',
          startDate: DateTime.now().add(const Duration(days: 14)),
          endDate: DateTime.now().add(const Duration(days: 19)),
          tripType: 'Adventure',
          budget: 25000,
          inviteCode: normalized,
          status: 'upcoming',
          memberCount: 5,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      final list = [...state.trips.where((t) => t.id != existingTrip.id), existingTrip];
      state = state.copyWith(trips: list, activeTripId: existingTrip.id);
      return existingTrip;
    }
  }

  void setActiveTrip(String tripId) {
    state = state.copyWith(activeTripId: tripId);
  }
}

final tripsProvider = NotifierProvider<TripsNotifier, TripsState>(TripsNotifier.new);

final activeTripProvider = Provider<TripModel?>((ref) {
  return ref.watch(tripsProvider).activeTrip;
});
