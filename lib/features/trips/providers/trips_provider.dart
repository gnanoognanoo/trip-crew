import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/core/services/analytics_service.dart';
import 'package:tripcrew/core/services/supabase_service.dart';
import 'package:tripcrew/features/auth/models/user_profile.dart';
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
      return trips.firstWhere((t) => t.isActive);
    } catch (_) {
      return trips.isNotEmpty ? trips.first : null;
    }
  }

  List<TripModel> get upcomingTrips {
    final activeId = activeTrip?.id;
    return trips.where((t) => t.id != activeId || t.status == 'upcoming' || !t.isActive).toList();
  }

  List<TripModel> get completedTrips =>
      trips.where((t) => !t.isActive && t.status == 'completed').toList();

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
  StreamSubscription? _tripsSub;

  @override
  TripsState build() {
    ref.onDispose(() {
      _tripsSub?.cancel();
    });

    final authState = ref.watch(authProvider);

    if (authState.user != null) {
      _listenToUserTrips(authState.user!.uid);
      return const TripsState(isLoading: true);
    }

    return const TripsState(isLoading: false, trips: []);
  }

  Future<void> fetchUserTrips(String uid) async {
    developer.log('[TRIPS_DEBUG] fetchUserTrips START | firebase uid = $uid', name: 'TripsNotifier');
    developer.log('[TRIPS_DEBUG] Supabase.isInitialized = ${SupabaseService.isInitialized}', name: 'TripsNotifier');
    if (SupabaseService.isInitialized) {
      developer.log('[TRIPS_DEBUG] Supabase session user = ${SupabaseService.client.auth.currentUser?.id}', name: 'TripsNotifier');
    }

    if (!SupabaseService.isInitialized) {
      state = state.copyWith(isLoading: false);
      developer.log('[TRIPS_DEBUG] Aborting: Supabase is not initialized', name: 'TripsNotifier');
      return;
    }
    try {
      final loadedTrips = <TripModel>[];
      final seenIds = <String>{};

      // 1. Fetch via trip_members membership
      try {
        developer.log('[TRIPS_DEBUG] membership query START', name: 'TripsNotifier');
        final memberRows = await SupabaseService.client
            .from('trip_members')
            .select('trip_id, trips(*)')
            .eq('user_id', uid);

        developer.log('[TRIPS_DEBUG] membership query RESULT = ${memberRows.length} rows', name: 'TripsNotifier');

        for (final row in memberRows) {
          final tripMap = row['trips'] as Map<String, dynamic>?;
          if (tripMap != null) {
            final tid = tripMap['id'] as String;
            seenIds.add(tid);
            loadedTrips.add(TripModel.fromMap(tripMap, tid));
          }
        }
      } catch (e) {
        developer.log('[TRIPS_DEBUG] membership query ERROR = $e', name: 'TripsNotifier');
      }

      // 2. Fallback: fetch trips created by this user directly
      try {
        developer.log('[TRIPS_DEBUG] created_by query START', name: 'TripsNotifier');
        final createdRows = await SupabaseService.client
            .from('trips')
            .select()
            .eq('created_by', uid);

        developer.log('[TRIPS_DEBUG] created_by query RESULT = ${createdRows.length} rows', name: 'TripsNotifier');

        for (final tripMap in createdRows) {
          final tid = tripMap['id'] as String;
          if (!seenIds.contains(tid)) {
            seenIds.add(tid);
            loadedTrips.add(TripModel.fromMap(tripMap, tid));
          }
        }
      } catch (e) {
        developer.log('[TRIPS_DEBUG] created_by query ERROR = $e', name: 'TripsNotifier');
      }

      state = state.copyWith(
        isLoading: false,
        trips: loadedTrips,
        activeTripId: state.activeTripId ?? (loadedTrips.isNotEmpty ? loadedTrips.first.id : null),
      );

      developer.log('[TRIPS_DEBUG] parsed trip count = ${loadedTrips.length}', name: 'TripsNotifier');
      developer.log('[TRIPS_DEBUG] trip IDs = ${loadedTrips.map((t) => t.id).toList()}', name: 'TripsNotifier');
      developer.log('[TRIPS_DEBUG] trip statuses = ${loadedTrips.map((t) => t.status).toList()}', name: 'TripsNotifier');
      developer.log('[TRIPS_DEBUG] isActive values = ${loadedTrips.map((t) => t.isActive).toList()}', name: 'TripsNotifier');
      developer.log('[TRIPS_DEBUG] upcomingTrips count = ${state.upcomingTrips.length}', name: 'TripsNotifier');
    } catch (e) {
      developer.log('[TRIPS_DEBUG] fetchUserTrips FATAL ERROR = $e', name: 'TripsNotifier');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void _listenToUserTrips(String uid) {
    _tripsSub?.cancel();
    fetchUserTrips(uid);

    if (SupabaseService.isInitialized) {
      try {
        _tripsSub = SupabaseService.client
            .from('trips')
            .stream(primaryKey: ['id'])
            .listen((_) {
              fetchUserTrips(uid);
            });
      } catch (_) {}
    }
  }

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

  static String normalizeInviteCode(String raw) {
    final cleaned = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (cleaned.startsWith('TC') && cleaned.length == 10) {
      return 'TC-${cleaned.substring(2, 6)}-${cleaned.substring(6, 10)}';
    } else if (cleaned.length == 8) {
      return 'TC-${cleaned.substring(0, 4)}-${cleaned.substring(4, 8)}';
    }
    return raw.trim().toUpperCase();
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
    final inviteCode = generateInviteCode();
    final tripId = 'trip_${DateTime.now().millisecondsSinceEpoch}';
    final uid = user?.uid ?? 'creator';

    final newTrip = TripModel(
      id: tripId,
      ownerId: uid,
      name: name.trim(),
      startingPlace: startingPlace.trim(),
      destination: destination.trim(),
      startDate: startDate,
      endDate: endDate,
      tripType: tripType,
      budget: budget,
      currency: currency,
      inviteCode: inviteCode,
      status: 'active',
      memberCount: 1,
      totalSpendingPaise: 0,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    if (SupabaseService.isInitialized) {
      try {
        await SupabaseService.client.from('trips').insert({
          'id': tripId,
          'title': name.trim(),
          'destination': destination.trim(),
          'start_date': startDate.toIso8601String(),
          'end_date': endDate.toIso8601String(),
          'created_by': uid,
          'member_count': 1,
          'invite_code': inviteCode,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });

        await SupabaseService.client.from('trip_members').insert({
          'id': 'tm_${DateTime.now().millisecondsSinceEpoch}',
          'trip_id': tripId,
          'user_id': uid,
          'role': 'owner',
          'joined_at': DateTime.now().toIso8601String(),
        });

        await SupabaseService.client.from('trip_invites').insert({
          'id': 'inv_${DateTime.now().millisecondsSinceEpoch}',
          'trip_id': tripId,
          'invite_code': inviteCode,
          'created_by': uid,
          'created_at': DateTime.now().toIso8601String(),
        });
      } catch (_) {}
    }

    await AnalyticsService.logTripCreated(tripId, tripType);

    final updated = [newTrip, ...state.trips];
    state = state.copyWith(trips: updated, activeTripId: tripId);

    return newTrip;
  }

  Future<TripModel?> joinTripByCode(String code) async {
    final normalized = normalizeInviteCode(code);
    var user = ref.read(authProvider).user;
    if (user == null && !SupabaseService.isInitialized) {
      user = UserProfile(
        uid: 'test_user',
        name: 'Test User',
        email: 'test@example.com',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }
    if (user == null) {
      throw Exception('You must be signed in to join a trip.');
    }

    if (SupabaseService.isInitialized) {
      final inviteRes = await SupabaseService.client
          .from('trip_invites')
          .select()
          .eq('invite_code', normalized)
          .maybeSingle();

      if (inviteRes == null) {
        throw Exception('Invalid or expired invite code.');
      }

      final isRevoked = inviteRes['is_revoked'] as bool? ?? false;
      if (isRevoked) {
        throw Exception('This invite code has been revoked by the trip owner.');
      }

      final tripId = inviteRes['trip_id'] as String;
      final tripRes = await SupabaseService.client
          .from('trips')
          .select()
          .eq('id', tripId)
          .single();

      final currentMemberCount = (tripRes['member_count'] as num?)?.toInt() ?? 1;

      final existingMember = await SupabaseService.client
          .from('trip_members')
          .select()
          .eq('trip_id', tripId)
          .eq('user_id', user.uid)
          .maybeSingle();

      if (existingMember != null) {
        state = state.copyWith(activeTripId: tripId);
        return TripModel.fromMap(tripRes, tripId);
      }

      if (currentMemberCount >= AppConstants.maxCrewMembers) {
        throw Exception('This trip has reached the maximum allowed crew size of ${AppConstants.maxCrewMembers} members.');
      }

      await SupabaseService.client.from('trip_members').insert({
        'id': 'tm_${DateTime.now().millisecondsSinceEpoch}',
        'trip_id': tripId,
        'user_id': user.uid,
        'role': 'member',
        'joined_at': DateTime.now().toIso8601String(),
      });

      await SupabaseService.client
          .from('trips')
          .update({'member_count': currentMemberCount + 1})
          .eq('id', tripId);

      await AnalyticsService.logTripJoined(tripId);

      final updatedTripRes = await SupabaseService.client
          .from('trips')
          .select()
          .eq('id', tripId)
          .single();

      final joinedTrip = TripModel.fromMap(updatedTripRes, tripId);
      state = state.copyWith(activeTripId: tripId);
      await fetchUserTrips(user.uid);
      return joinedTrip;
    } else {
      final found = state.trips.where((t) => t.inviteCode == normalized).firstOrNull;
      if (found != null) {
        if (found.memberCount >= AppConstants.maxCrewMembers) {
          throw Exception('This trip has reached the maximum allowed crew size of ${AppConstants.maxCrewMembers} members.');
        }
        state = state.copyWith(activeTripId: found.id);
        return found;
      }
      throw Exception('Invite code not found.');
    }
  }

  Future<void> removeMember({
    required String tripId,
    required String memberUid,
  }) async {
    if (SupabaseService.isInitialized) {
      final tripRes = await SupabaseService.client
          .from('trips')
          .select()
          .eq('id', tripId)
          .maybeSingle();

      if (tripRes != null) {
        final ownerId = tripRes['created_by'] as String?;
        if (memberUid == ownerId) {
          throw Exception('The trip owner cannot be removed from the crew.');
        }

        final currentCount = (tripRes['member_count'] as num?)?.toInt() ?? 1;
        final newCount = (currentCount - 1).clamp(1, AppConstants.maxCrewMembers);

        await SupabaseService.client
            .from('trip_members')
            .delete()
            .eq('trip_id', tripId)
            .eq('user_id', memberUid);

        await SupabaseService.client
            .from('trips')
            .update({'member_count': newCount})
            .eq('id', tripId);
      }
    }
  }

  Future<void> revokeInvite({
    required String tripId,
    required String inviteCode,
  }) async {
    final normalized = normalizeInviteCode(inviteCode);
    if (SupabaseService.isInitialized) {
      await SupabaseService.client
          .from('trip_invites')
          .update({'is_revoked': true})
          .eq('trip_id', tripId)
          .eq('invite_code', normalized);
    }
  }

  void setActiveTrip(String tripId) {
    state = state.copyWith(activeTripId: tripId);
  }

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
