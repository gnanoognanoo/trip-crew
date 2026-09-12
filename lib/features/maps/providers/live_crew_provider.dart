import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tripcrew/core/services/firebase_service.dart';
import 'package:tripcrew/core/services/live_crew_service.dart';
import 'package:tripcrew/features/auth/providers/auth_provider.dart';
import 'package:tripcrew/features/maps/models/live_location_model.dart';
import 'package:tripcrew/features/maps/utils/location_calculator.dart';
import 'package:tripcrew/features/pulse/models/trip_pulse.dart';
import 'package:tripcrew/features/trips/models/trip_model.dart';
import 'package:tripcrew/features/trips/providers/trips_provider.dart';

class LiveCrewState {
  final bool isLoading;
  final String? errorMessage;
  final List<LiveLocationModel> members;
  final LiveLocationModel? myLocation;
  final Map<String, double> distances; // memberUid -> distance in meters
  final Map<String, double>
  bearings; // memberUid -> relative bearing in degrees
  final GroupStatus groupStatus;
  final LocationServiceState serviceState;
  final bool isSharing;
  final String sharingMode;
  final DateTime? sharingUntil;
  final Map<String, int> crewPulseCounts; // PulseType -> active count
  final List<String> combinedInsights; // Non-AI contextual insights
  final List<LiveLocationModel>
  emergencyMembers; // Members with active emergency

  const LiveCrewState({
    this.isLoading = true,
    this.errorMessage,
    this.members = const [],
    this.myLocation,
    this.distances = const {},
    this.bearings = const {},
    this.groupStatus = const GroupStatus(
      isTogether: true,
      awayCount: 0,
      totalSharing: 0,
      statusTitle: 'Locating Crew...',
      statusSubtitle: 'Connecting to live crew location',
    ),
    this.serviceState = LocationServiceState.off,
    this.isSharing = false,
    this.sharingMode = 'off',
    this.sharingUntil,
    this.crewPulseCounts = const {},
    this.combinedInsights = const [],
    this.emergencyMembers = const [],
  });

  LiveCrewState copyWith({
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    List<LiveLocationModel>? members,
    LiveLocationModel? myLocation,
    bool clearMyLocation = false,
    Map<String, double>? distances,
    Map<String, double>? bearings,
    GroupStatus? groupStatus,
    LocationServiceState? serviceState,
    bool? isSharing,
    String? sharingMode,
    DateTime? sharingUntil,
    Map<String, int>? crewPulseCounts,
    List<String>? combinedInsights,
    List<LiveLocationModel>? emergencyMembers,
  }) {
    return LiveCrewState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      members: members ?? this.members,
      myLocation: clearMyLocation ? null : (myLocation ?? this.myLocation),
      distances: distances ?? this.distances,
      bearings: bearings ?? this.bearings,
      groupStatus: groupStatus ?? this.groupStatus,
      serviceState: serviceState ?? this.serviceState,
      isSharing: isSharing ?? this.isSharing,
      sharingMode: sharingMode ?? this.sharingMode,
      sharingUntil: sharingUntil ?? this.sharingUntil,
      crewPulseCounts: crewPulseCounts ?? this.crewPulseCounts,
      combinedInsights: combinedInsights ?? this.combinedInsights,
      emergencyMembers: emergencyMembers ?? this.emergencyMembers,
    );
  }
}

final liveCrewProvider = NotifierProvider<LiveCrewNotifier, LiveCrewState>(
  LiveCrewNotifier.new,
);

class LiveCrewNotifier extends Notifier<LiveCrewState> {
  StreamSubscription? _locationsSub;
  StreamSubscription? _pulsesSub;
  StreamSubscription? _membersSub;
  StreamSubscription? _statusSub;

  final Map<String, Map<String, dynamic>> _tripMembers = {};
  final Map<String, LiveLocationModel> _rawLocations = {};
  final Map<String, TripPulse> _activePulses = {};

  @override
  LiveCrewState build() {
    ref.onDispose(() {
      _locationsSub?.cancel();
      _pulsesSub?.cancel();
      _membersSub?.cancel();
      _statusSub?.cancel();
    });

    _listenToStatus();
    _listenToCrewLocations();

    // Automatically stop sharing and clear coordinates if trip ends or is marked completed
    ref.listen<TripModel?>(activeTripProvider, (previous, next) {
      if (next == null ||
          next.status == 'completed' ||
          DateTime.now().isAfter(next.endDate)) {
        if (state.isSharing) {
          stopSharing();
        }
      }
    });

    return LiveCrewState(
      isSharing: LiveCrewService.instance.isSharing,
      sharingMode: LiveCrewService.instance.activeSharingMode,
      sharingUntil: LiveCrewService.instance.activeSharingUntil,
    );
  }

  void _listenToStatus() {
    _statusSub = LiveCrewService.instance.statusStream.listen((status) {
      state = state.copyWith(
        serviceState: status,
        isSharing: LiveCrewService.instance.isSharing,
        sharingMode: LiveCrewService.instance.activeSharingMode,
        sharingUntil: LiveCrewService.instance.activeSharingUntil,
      );
    });

    LiveCrewService.instance.checkStatus().then((status) {
      state = state.copyWith(serviceState: status);
    });
  }

  void _listenToCrewLocations() {
    final activeTrip = ref.watch(activeTripProvider);

    if (activeTrip == null) {
      state = state.copyWith(isLoading: false);
      return;
    }

    if (!FirebaseService.isInitialized) {
      // Local development fallback
      state = state.copyWith(
        isLoading: false,
        members: [],
        groupStatus: const GroupStatus(
          isTogether: true,
          awayCount: 0,
          totalSharing: 0,
          statusTitle: '🟢 Everyone is together',
          statusSubtitle: 'Ready for live sharing',
        ),
      );
      return;
    }

    _locationsSub?.cancel();
    _pulsesSub?.cancel();
    _membersSub?.cancel();

    // 1. Listen to trip members to discover all crew members
    _membersSub = FirebaseFirestore.instance
        .collection('trips')
        .doc(activeTrip.id)
        .collection('members')
        .snapshots()
        .listen((snap) {
          _tripMembers.clear();
          for (final doc in snap.docs) {
            _tripMembers[doc.id] = doc.data();
          }
          _rebuildCrewState();
        });

    // 2. Listen to pulses to show member status (Hungry, Break, Tired, Emergency, etc.)
    _pulsesSub = FirebaseFirestore.instance
        .collection('trips')
        .doc(activeTrip.id)
        .collection('pulses')
        .snapshots()
        .listen((snap) {
          _activePulses.clear();
          for (final doc in snap.docs) {
            final pulse = TripPulse.fromMap(doc.data(), doc.id);
            if (pulse.isCurrentlyActive) {
              _activePulses[doc.id] = pulse;
            }
          }
          _rebuildCrewState();
        });

    // 3. Listen to live crew location updates
    _locationsSub = FirebaseFirestore.instance
        .collection('trips')
        .doc(activeTrip.id)
        .collection('locations')
        .snapshots()
        .listen(
          (snapshot) {
            _rawLocations.clear();
            for (final doc in snapshot.docs) {
              _rawLocations[doc.id] = LiveLocationModel.fromMap(
                doc.data(),
                doc.id,
              );
            }
            _rebuildCrewState();
          },
          onError: (err) {
            state = state.copyWith(
              isLoading: false,
              errorMessage: 'Could not load crew locations. Check connection.',
            );
          },
        );
  }

  void _rebuildCrewState() {
    final activeTrip = ref.read(activeTripProvider);
    final currentUser = ref.read(authProvider).user;
    final currentUid = currentUser?.uid;
    if (activeTrip == null) return;

    // Union of all known member UIDs in the trip
    final allUids = <String>{
      ..._tripMembers.keys,
      ..._rawLocations.keys,
      ..._activePulses.keys,
    };

    LiveLocationModel? myLoc;
    final memberMap = <String, LiveLocationModel>{};

    for (final uid in allUids) {
      final rawLoc = _rawLocations[uid];
      final pulse = _activePulses[uid];
      final memberInfo = _tripMembers[uid];
      final displayName =
          rawLoc?.displayName ??
          memberInfo?['name'] as String? ??
          pulse?.memberName ??
          (uid == currentUid ? (currentUser?.name ?? 'You') : 'Crew Member');
      final photoUrl = rawLoc?.photoUrl ?? memberInfo?['photoUrl'] as String?;

      final LiveLocationModel model;
      if (rawLoc != null) {
        model = rawLoc.copyWith(
          displayName: displayName,
          photoUrl: photoUrl,
          activePulse: pulse,
          lastPulse: pulse?.displayLabel,
          clearPulse: pulse == null,
        );
      } else {
        model = LiveLocationModel(
          uid: uid,
          displayName: displayName,
          photoUrl: photoUrl,
          updatedAt: pulse?.createdAt ?? DateTime.now(),
          isSharing: false,
          sharingMode: 'off',
          activePulse: pulse,
          lastPulse: pulse?.displayLabel,
        );
      }

      if (currentUid != null && uid == currentUid) {
        myLoc = model;
        // If own stored document has expired, perform idempotent cleanup to purge coordinates from Firestore
        if (model.isExpired && (model.hasCoordinates || model.isSharing)) {
          LiveCrewService.instance.checkAndCleanupExpiredLocation(
            tripId: activeTrip.id,
            uid: currentUid,
          );
        }
      } else {
        memberMap[uid] = model;
      }
    }

    final isMyLocValid =
        myLoc != null &&
        myLoc.isSharing &&
        myLoc.hasCoordinates &&
        !myLoc.isExpired;

    // Distances & Bearings
    final distances = <String, double>{};
    final bearings = <String, double>{};
    final activeDistances = <double>[];

    final effectiveMyLoc = isMyLocValid
        ? myLoc
        : (state.isSharing && LiveCrewService.instance.lastPosition != null
              ? LiveLocationModel(
                  uid: currentUid ?? 'me',
                  displayName: currentUser?.name ?? 'You',
                  latitude: LiveCrewService.instance.lastPosition!.latitude,
                  longitude: LiveCrewService.instance.lastPosition!.longitude,
                  accuracy: LiveCrewService.instance.lastPosition!.accuracy,
                  updatedAt: DateTime.now(),
                  sharingMode: LiveCrewService.instance.activeSharingMode,
                  sharingUntil: LiveCrewService.instance.activeSharingUntil,
                  isSharing: true,
                  activePulse: myLoc?.activePulse,
                  lastPulse: myLoc?.lastPulse,
                )
              : null);

    if (effectiveMyLoc != null &&
        effectiveMyLoc.hasCoordinates &&
        !effectiveMyLoc.isExpired) {
      for (final member in memberMap.values) {
        if (member.isSharing && !member.isExpired && member.hasCoordinates) {
          final d = LocationCalculator.calculateDistance(
            effectiveMyLoc.latitude!,
            effectiveMyLoc.longitude!,
            member.latitude!,
            member.longitude!,
          );
          final b = LocationCalculator.calculateBearing(
            effectiveMyLoc.latitude!,
            effectiveMyLoc.longitude!,
            member.latitude!,
            member.longitude!,
          );
          distances[member.uid] = d;
          bearings[member.uid] = b;
          activeDistances.add(d);
        }
      }
    }

    final groupStatus = GroupStatus.evaluate(activeDistances);

    // Aggregate pulse counts across all active pulses in the trip
    final pulseCounts = <String, int>{};
    for (final pulse in _activePulses.values) {
      if (pulse.isCurrentlyActive) {
        pulseCounts[pulse.pulseType] = (pulseCounts[pulse.pulseType] ?? 0) + 1;
      }
    }

    // Local non-AI contextual crew insights
    final insights = <String>[];
    if ((pulseCounts['Hungry'] ?? 0) >= 2) {
      insights.add('${pulseCounts['Hungry']} crew members are hungry.');
    }
    if ((pulseCounts['Need a Break'] ?? 0) >= 2) {
      insights.add('Your crew may need a break.');
    }
    if ((pulseCounts['Tired'] ?? 0) >= 2) {
      insights.add('${pulseCounts['Tired']} crew members are tired.');
    }
    if ((pulseCounts['Need Fuel'] ?? 0) >= 2) {
      insights.add('${pulseCounts['Need Fuel']} crew members need fuel.');
    }

    // Distance + Pulse insights: member > togetherThreshold AND has active pulse
    for (final member in memberMap.values) {
      final d = distances[member.uid];
      if (d != null && d > kTogetherThresholdMeters && member.hasActivePulse) {
        insights.add(
          '${member.displayName} is ${LocationCalculator.formatDistance(d)} • ${member.activePulse!.pulseType}',
        );
      }
    }

    // Identify any members with an active Emergency pulse
    final emergencies = <LiveLocationModel>[];
    for (final m in [...memberMap.values, ?myLoc]) {
      if (m.hasActivePulse && m.activePulse!.isEmergency) {
        emergencies.add(m);
      }
    }

    state = state.copyWith(
      isLoading: false,
      members: memberMap.values.toList(),
      myLocation: isMyLocValid ? myLoc : null,
      clearMyLocation: !isMyLocValid,
      distances: distances,
      bearings: bearings,
      groupStatus: groupStatus,
      crewPulseCounts: pulseCounts,
      combinedInsights: insights,
      emergencyMembers: emergencies,
      clearError: true,
    );
  }

  Future<void> startSharing({
    String? tripId,
    String? tripName,
    String? uid,
    String? displayName,
    String? photoUrl,
    String? sharingMode,
    String? mode,
    required DateTime until,
  }) async {
    final activeTrip = ref.read(activeTripProvider);
    final user = ref.read(authProvider).user;
    final effectiveTripId = tripId ?? activeTrip?.id ?? '';
    final effectiveTripName = tripName ?? activeTrip?.name ?? 'Trip';
    final effectiveUid = uid ?? user?.uid ?? 'me';
    final effectiveDisplayName = displayName ?? user?.name ?? 'You';
    final effectivePhotoUrl = photoUrl ?? user?.photoUrl;
    final effectiveMode = sharingMode ?? mode ?? '1_hour';

    final result = await LiveCrewService.instance.startSharing(
      tripId: effectiveTripId,
      tripName: effectiveTripName,
      uid: effectiveUid,
      displayName: effectiveDisplayName,
      photoUrl: effectivePhotoUrl,
      sharingMode: effectiveMode,
      sharingUntil: until,
    );

    state = state.copyWith(
      serviceState: result,
      isSharing: LiveCrewService.instance.isSharing,
      sharingMode: LiveCrewService.instance.activeSharingMode,
      sharingUntil: until,
    );
  }

  Future<void> stopSharing() async {
    await LiveCrewService.instance.stopSharing();
    state = state.copyWith(
      isSharing: false,
      sharingMode: 'off',
      sharingUntil: null,
      clearMyLocation: true,
    );
  }

  Future<void> openSettings() async {
    if (state.serviceState == LocationServiceState.serviceDisabled) {
      await LiveCrewService.instance.openLocationSettings();
    } else {
      await LiveCrewService.instance.openAppSettings();
    }
  }
}
