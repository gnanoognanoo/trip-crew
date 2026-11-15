import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
        final selected = trips.firstWhere((t) => t.id == activeTripId);
        // If the explicitly chosen trip is not over/past/cancelled, return it
        if (!selected.isPast && !selected.isCompleted && !selected.isCancelled) {
          return selected;
        }
      } catch (_) {}
    }
    try {
      return trips.firstWhere((t) => t.isOngoing && !t.isCancelled);
    } catch (_) {}
    try {
      return trips.firstWhere((t) => t.isUpcoming && !t.isCancelled);
    } catch (_) {}
    // Even though trips exist, if they are past or completed, do NOT treat them as active trips
    return null;
  }

  List<TripModel> get ongoingTrips =>
      trips.where((t) => t.isOngoing && !t.isCancelled).toList();

  List<TripModel> get upcomingTrips =>
      trips.where((t) => t.isUpcoming && !t.isCancelled).toList();

  List<TripModel> get completedTrips =>
      trips.where((t) => t.isCompleted || (t.isPast && !t.isCancelled)).toList();

  List<TripModel> get pastTrips =>
      trips.where((t) => t.isPast || t.isCompleted || t.isCancelled).toList();

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

      // 3. Reconcile user-selected status overrides, budget & cover photo persisted locally
      try {
        final prefs = await SharedPreferences.getInstance();
        for (int i = 0; i < loadedTrips.length; i++) {
          final trip = loadedTrips[i];
          final savedStatus = prefs.getString('trip_status_${trip.id}');
          final savedBudget = prefs.getDouble('trip_budget_${trip.id}');
          final savedCover = prefs.getString('trip_cover_photo_${trip.id}');

          double finalBudget = trip.budget;
          if (savedBudget != null && savedBudget > 0) {
            finalBudget = savedBudget;
          } else if (finalBudget <= 0) {
            finalBudget = 2500.0;
          }

          String? finalCover = trip.coverPhotoUrl;
          if (finalCover == null || finalCover.isEmpty) {
            finalCover = savedCover;
          }
          if (finalCover == null || finalCover.isEmpty) {
            if (trip.destination.toLowerCase().contains('pondi')) {
              finalCover =
                  'https://images.unsplash.com/photo-1582510003544-4d00b7f74220?w=1200&auto=format&fit=crop&q=80';
            }
          }

          final savedStartLat = prefs.getDouble('trip_start_lat_${trip.id}');
          final savedStartLng = prefs.getDouble('trip_start_lng_${trip.id}');
          final savedDestLat = prefs.getDouble('trip_dest_lat_${trip.id}');
          final savedDestLng = prefs.getDouble('trip_dest_lng_${trip.id}');
          final savedStartAddr = prefs.getString('trip_start_addr_${trip.id}');
          final savedDestAddr = prefs.getString('trip_dest_addr_${trip.id}');

          final isNowActive = savedStatus != null ? (savedStatus == 'active') : trip.isActive;
          final finalStatus = savedStatus ?? trip.status;

          loadedTrips[i] = trip.copyWith(
            status: finalStatus,
            isActive: isNowActive,
            budget: finalBudget,
            coverPhotoUrl: finalCover,
            startLat: savedStartLat ?? trip.startLat,
            startLng: savedStartLng ?? trip.startLng,
            destLat: savedDestLat ?? trip.destLat,
            destLng: savedDestLng ?? trip.destLng,
            startingPlaceAddress: savedStartAddr ?? trip.startingPlaceAddress,
            destinationAddress: savedDestAddr ?? trip.destinationAddress,
          );
        }
      } catch (_) {}

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
    String? coverPhotoUrl,
    double? startLat,
    double? startLng,
    double? destLat,
    double? destLng,
    String? startingPlaceAddress,
    String? destinationAddress,
  }) async {
    var user = ref.read(authProvider).user;
    if (user == null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        String? travelerUid = prefs.getString('persistent_traveler_uid');
        String? travelerName = prefs.getString('persistent_traveler_name');
        if (travelerUid == null || travelerUid.isEmpty) {
          final randDigits = (DateTime.now().millisecondsSinceEpoch % 9000 + 1000).toString();
          travelerUid = 'traveler_${DateTime.now().millisecondsSinceEpoch}_$randDigits';
          travelerName = 'Traveler $randDigits';
          await prefs.setString('persistent_traveler_uid', travelerUid);
          await prefs.setString('persistent_traveler_name', travelerName);
        }
        user = UserProfile(
          uid: travelerUid,
          name: travelerName ?? 'Traveler',
          email: '$travelerUid@tripcrew.app',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        ref.read(authProvider.notifier).setGuestUser(user);
      } catch (_) {}
    }
    final inviteCode = generateInviteCode();
    final tripId = 'trip_${DateTime.now().millisecondsSinceEpoch}';
    final uid = user?.uid ?? 'creator';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final String initialStatus = startDate.isAfter(today) ? 'upcoming' : 'active';
    final bool initialIsActive = initialStatus == 'active';

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
      status: initialStatus,
      isActive: initialIsActive,
      memberCount: 1,
      totalSpendingPaise: 0,
      coverPhotoUrl: coverPhotoUrl,
      startLat: startLat,
      startLng: startLng,
      destLat: destLat,
      destLng: destLng,
      startingPlaceAddress: startingPlaceAddress,
      destinationAddress: destinationAddress,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // Persist user-specified budget, cover photo and coordinates in local cache
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('trip_budget_$tripId', budget);
      if (coverPhotoUrl != null && coverPhotoUrl.isNotEmpty) {
        await prefs.setString('trip_cover_photo_$tripId', coverPhotoUrl);
      }
      if (startLat != null) await prefs.setDouble('trip_start_lat_$tripId', startLat);
      if (startLng != null) await prefs.setDouble('trip_start_lng_$tripId', startLng);
      if (destLat != null) await prefs.setDouble('trip_dest_lat_$tripId', destLat);
      if (destLng != null) await prefs.setDouble('trip_dest_lng_$tripId', destLng);
      if (startingPlaceAddress != null) {
        await prefs.setString('trip_start_addr_$tripId', startingPlaceAddress);
      }
      if (destinationAddress != null) {
        await prefs.setString('trip_dest_addr_$tripId', destinationAddress);
      }
    } catch (_) {}

    developer.log(
      '[TRIP_CREATE_DEBUG] createTrip START | uid=$uid | tripId=$tripId | title=${name.trim()} | budget=$budget | coverPhotoUrl=$coverPhotoUrl | startDate=$startDate | status=$initialStatus',
      name: 'TripsNotifier',
    );

    if (SupabaseService.isInitialized) {
      try {
        final tripsInsertPayload = {
          'id': tripId,
          'title': name.trim(),
          'destination': destination.trim(),
          'start_date': startDate.toIso8601String(),
          'end_date': endDate.toIso8601String(),
          'created_by': uid,
          'member_count': 1,
          'invite_code': inviteCode,
          'budget': budget,
          'status': initialStatus,
          if (startingPlace.isNotEmpty) 'starting_place': startingPlace.trim(),
          if (coverPhotoUrl != null && coverPhotoUrl.isNotEmpty)
            'cover_photo_url': coverPhotoUrl,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        };
        developer.log(
          '[TRIP_CREATE_DEBUG] trips INSERT payload = $tripsInsertPayload',
          name: 'TripsNotifier',
        );

        final tripsRes = await SupabaseService.client
            .from('trips')
            .insert(tripsInsertPayload)
            .select();
        developer.log(
          '[TRIP_CREATE_DEBUG] trips INSERT response = $tripsRes',
          name: 'TripsNotifier',
        );

        final memberInsertPayload = {
          'id': 'tm_${DateTime.now().millisecondsSinceEpoch}',
          'trip_id': tripId,
          'user_id': uid,
          'role': 'owner',
          'joined_at': DateTime.now().toIso8601String(),
        };
        developer.log(
          '[TRIP_CREATE_DEBUG] trip_members INSERT payload = $memberInsertPayload',
          name: 'TripsNotifier',
        );

        final memberRes = await SupabaseService.client
            .from('trip_members')
            .insert(memberInsertPayload)
            .select();
        developer.log(
          '[TRIP_CREATE_DEBUG] trip_members INSERT response = $memberRes',
          name: 'TripsNotifier',
        );

        await SupabaseService.client.from('trip_invites').insert({
          'id': 'inv_${DateTime.now().millisecondsSinceEpoch}',
          'trip_id': tripId,
          'invite_code': inviteCode,
          'created_by': uid,
          'created_at': DateTime.now().toIso8601String(),
        });
      } catch (e, stack) {
        developer.log(
          '[TRIP_CREATE_DEBUG] Supabase trip creation ERROR = $e',
          name: 'TripsNotifier',
          stackTrace: stack,
        );
      }
    }

    await AnalyticsService.logTripCreated(tripId, tripType);

    final updated = [newTrip, ...state.trips];
    state = state.copyWith(trips: updated, activeTripId: tripId);

    return newTrip;
  }

  Future<TripModel?> joinTripByCode(String code) async {
    final normalized = normalizeInviteCode(code);
    var user = ref.read(authProvider).user;
    if (user == null) {
      final prefs = await SharedPreferences.getInstance();
      String? travelerUid = prefs.getString('persistent_traveler_uid');
      String? travelerName = prefs.getString('persistent_traveler_name');
      if (travelerUid == null || travelerUid.isEmpty) {
        final randDigits = (DateTime.now().millisecondsSinceEpoch % 9000 + 1000).toString();
        travelerUid = 'traveler_${DateTime.now().millisecondsSinceEpoch}_$randDigits';
        travelerName = 'Traveler $randDigits';
        await prefs.setString('persistent_traveler_uid', travelerUid);
        await prefs.setString('persistent_traveler_name', travelerName);
      }
      user = UserProfile(
        uid: travelerUid,
        name: travelerName ?? 'Traveler',
        email: '$travelerUid@tripcrew.app',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      ref.read(authProvider.notifier).setGuestUser(user);

      if (SupabaseService.isInitialized) {
        try {
          await SupabaseService.client.from('profiles').upsert({
            'id': travelerUid,
            'full_name': user.name,
            'display_name': user.name,
            'email': user.email,
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          });
        } catch (_) {}
      }
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

      try {
        await SupabaseService.client.from('profiles').upsert({
          'id': user.uid,
          'display_name': user.name,
          'email': user.email,
          'updated_at': DateTime.now().toIso8601String(),
        });
      } catch (_) {}

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

        // Update local trip model across app
        state = state.copyWith(
          trips: state.trips.map((t) => t.id == tripId ? t.copyWith(memberCount: newCount) : t).toList(),
        );

        try {
          final prefs = await SharedPreferences.getInstance();
          final savedList = prefs.getStringList('trip_crew_names_$tripId');
          if (savedList != null && savedList.length > 1) {
            final updated = List<String>.from(savedList);
            if (updated.length > newCount) {
              updated.removeRange(newCount, updated.length);
            }
            await prefs.setStringList('trip_crew_names_$tripId', updated);
          }
          final removedUids = prefs.getStringList('removed_crew_uids_$tripId') ?? [];
          if (!removedUids.contains(memberUid)) {
            removedUids.add(memberUid);
            await prefs.setStringList('removed_crew_uids_$tripId', removedUids);
          }
        } catch (_) {}
      }
    }
  }

  void updateLocalTripMemberCount(String tripId, int newCount) {
    state = state.copyWith(
      trips: state.trips.map((t) => t.id == tripId ? t.copyWith(memberCount: newCount) : t).toList(),
    );
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

  Future<TripModel> updateTrip({
    required String tripId,
    String? name,
    String? startingPlace,
    String? destination,
    DateTime? startDate,
    DateTime? endDate,
    double? budget,
    String? tripType,
  }) async {
    final existingIndex = state.trips.indexWhere((t) => t.id == tripId);
    if (existingIndex == -1) {
      throw Exception('Trip not found.');
    }
    final current = state.trips[existingIndex];

    final updatedTrip = current.copyWith(
      name: name?.trim(),
      startingPlace: startingPlace?.trim(),
      destination: destination?.trim(),
      startDate: startDate,
      endDate: endDate,
      budget: budget,
      tripType: tripType,
    );

    if (budget != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('trip_budget_$tripId', budget);
      } catch (_) {}
    }

    if (SupabaseService.isInitialized) {
      final payload = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (name != null) payload['title'] = name.trim();
      if (destination != null) payload['destination'] = destination.trim();
      if (startDate != null) payload['start_date'] = startDate.toIso8601String();
      if (endDate != null) payload['end_date'] = endDate.toIso8601String();
      if (budget != null) payload['budget'] = budget;
      if (startingPlace != null) payload['starting_place'] = startingPlace.trim();
      if (tripType != null) payload['trip_type'] = tripType;

      try {
        await SupabaseService.client
            .from('trips')
            .update(payload)
            .eq('id', tripId);
      } catch (e) {
        developer.log('Failed to update trip in Supabase: $e', name: 'TripsNotifier');
      }
    }

    final updatedList = List<TripModel>.from(state.trips);
    updatedList[existingIndex] = updatedTrip;
    state = state.copyWith(trips: updatedList);

    return updatedTrip;
  }

  Future<void> setTripStatus({
    required String tripId,
    required String status,
    bool? isActive,
  }) async {
    final active = isActive ?? (status == 'active');
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('trip_status_$tripId', status);
    } catch (_) {}

    if (SupabaseService.isInitialized) {
      try {
        await SupabaseService.client.from('trips').update({
          'status': status,
          'is_active': active,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', tripId);
      } catch (e) {
        developer.log('Failed to update trip status in Supabase: $e', name: 'TripsNotifier');
      }
    }

    final updatedList = state.trips.map((t) {
      if (t.id == tripId) {
        return t.copyWith(status: status, isActive: active);
      }
      return t;
    }).toList();

    state = state.copyWith(trips: updatedList);
  }

  Future<void> archiveTrip(String tripId) async {
    await setTripStatus(tripId: tripId, status: 'completed', isActive: false);
  }

  Future<void> deleteTrip(String tripId) async {
    final user = ref.read(authProvider).user;
    final trip = state.trips.where((t) => t.id == tripId).firstOrNull;
    if (trip != null && user != null && trip.ownerId.isNotEmpty && trip.ownerId != user.uid) {
      throw Exception('Only the trip owner can delete this trip.');
    }

    if (SupabaseService.isInitialized) {
      await SupabaseService.client.from('trips').delete().eq('id', tripId);
    }

    final updatedList = state.trips.where((t) => t.id != tripId).toList();
    final newActiveId = state.activeTripId == tripId
        ? (updatedList.isNotEmpty ? updatedList.first.id : null)
        : state.activeTripId;

    state = state.copyWith(trips: updatedList, activeTripId: newActiveId);
  }

  void setActiveTrip(String tripId) {
    state = state.copyWith(activeTripId: tripId);
  }

  Future<void> updateTripStatus(String tripId, String newStatus) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('trip_status_$tripId', newStatus);
    } catch (_) {}

    final updatedList = state.trips.map((t) {
      if (t.id == tripId) {
        final isNowActive = newStatus == 'active';
        return t.copyWith(
          status: newStatus,
          isActive: isNowActive,
        );
      }
      return t;
    }).toList();

    state = state.copyWith(trips: updatedList);

    if (SupabaseService.isInitialized) {
      try {
        await SupabaseService.client.from('trips').update({
          'status': newStatus,
          'is_active': newStatus == 'active',
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', tripId);
      } catch (e) {
        developer.log('[TRIP_STATUS_UPDATE_ERROR] $e', name: 'TripsNotifier');
      }
    }
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
        budget: 2500.0,
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
