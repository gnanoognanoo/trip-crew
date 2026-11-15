import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:tripcrew/core/services/live_crew_service.dart';
import 'package:tripcrew/core/services/location_service.dart';
import 'package:tripcrew/core/services/supabase_service.dart';
import 'package:tripcrew/core/services/trip_route_service.dart';
import 'package:tripcrew/features/auth/providers/auth_provider.dart';
import 'package:tripcrew/features/itinerary/models/itinerary_item.dart';
import 'package:tripcrew/features/maps/providers/live_crew_provider.dart';
import 'package:tripcrew/features/trips/models/trip_model.dart';
import 'package:tripcrew/features/trips/providers/trips_provider.dart';

class TripMapScreen extends ConsumerStatefulWidget {
  const TripMapScreen({super.key});

  @override
  ConsumerState<TripMapScreen> createState() => _TripMapScreenState();
}

class _TripMapScreenState extends ConsumerState<TripMapScreen> {
  final MapController _mapController = MapController();
  LatLng? _userLocation;
  bool _isLoading = true;
  List<ItineraryItem> _itineraryItems = [];
  final Map<String, LatLng> _resolvedCoords = {};
  TripRouteInfo? _tripRoute;
  Map<String, Map<String, dynamic>> _chatPinnedLocations = {};

  static const Map<String, LatLng> _cityCoordinates = {
    'marina': LatLng(13.0500, 80.2824),
    'marina beach': LatLng(13.0500, 80.2824),
    'chennai': LatLng(13.0827, 80.2707),
    'avadi': LatLng(13.1147, 80.1008),
    'pondy': LatLng(11.9416, 79.8083),
    'pondicherry': LatLng(11.9416, 79.8083),
    'bengaluru': LatLng(12.9716, 77.5946),
    'bangalore': LatLng(12.9716, 77.5946),
    'mumbai': LatLng(19.0760, 72.8777),
    'delhi': LatLng(28.6139, 77.2090),
    'goa': LatLng(15.2993, 74.1240),
  };

  @override
  void initState() {
    super.initState();
    _initMapData();
  }

  Future<void> _initMapData() async {
    await _checkUserLocation();
    await _loadCrewNames();
    await _loadItinerary();
    await _loadChatLocations();
    await _calculateTripRoute();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadChatLocations() async {
    final activeTrip = ref.read(activeTripProvider);
    if (activeTrip == null || !SupabaseService.isInitialized) return;
    try {
      final res = await SupabaseService.client
          .from('chat_messages')
          .select('id, user_id, user_name, latitude, longitude, created_at')
          .eq('trip_id', activeTrip.id)
          .eq('message_type', 'location')
          .order('created_at', ascending: false);
      final map = <String, Map<String, dynamic>>{};
      for (final row in res) {
        final uid = row['user_id']?.toString() ?? '';
        if (uid.isNotEmpty && !map.containsKey(uid) && row['latitude'] != null && row['longitude'] != null) {
          map[uid] = row;
        }
      }
      if (mounted) {
        setState(() {
          _chatPinnedLocations = map;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadCrewNames() async {
    // Loaded if needed in future
  }

  Future<void> _checkUserLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 4),
        ),
      );

      if (mounted) {
        setState(() {
          _userLocation = LatLng(position.latitude, position.longitude);
        });

        // Sync real live GPS coordinates to Supabase live_locations
        final activeTrip = ref.read(activeTripProvider);
        final currentUser = ref.read(authProvider).user;
        if (activeTrip != null && currentUser != null) {
          LiveCrewService.instance.updateSingleLocation(
            tripId: activeTrip.id,
            uid: currentUser.uid,
            displayName: currentUser.name,
            latitude: position.latitude,
            longitude: position.longitude,
            accuracy: position.accuracy,
            photoUrl: currentUser.photoUrl,
          );
        }
      }
    } catch (e) {
      developer.log('Error determining location: $e', name: 'TripMap');
    }
  }

  Future<void> _loadItinerary() async {
    final activeTrip = ref.read(activeTripProvider);
    if (activeTrip == null) return;

    if (SupabaseService.isInitialized) {
      try {
        final res = await SupabaseService.client
            .from('itinerary_items')
            .select()
            .eq('trip_id', activeTrip.id)
            .order('order', ascending: true);

        final items = (res as List)
            .map((doc) => ItineraryItem.fromMap(
                  Map<String, dynamic>.from(doc as Map),
                  doc['id']?.toString() ?? '',
                ))
            .toList();

        _itineraryItems = items;
      } catch (e) {
        developer.log('Failed to load itinerary: $e', name: 'TripMap');
      }
    }

    for (int i = 0; i < _itineraryItems.length; i++) {
      final item = _itineraryItems[i];
      if (item.latitude != null && item.longitude != null) {
        _resolvedCoords[item.id] = LatLng(item.latitude!, item.longitude!);
      }
    }
  }

  LatLng _getDestinationCoord(TripModel activeTrip) {
    if (activeTrip.destLat != null && activeTrip.destLng != null) {
      return LatLng(activeTrip.destLat!, activeTrip.destLng!);
    }
    final destClean = activeTrip.destination.toLowerCase().trim();
    if (destClean.contains('marina')) {
      return const LatLng(13.0500, 80.2824); // Marina Beach, Chennai
    }
    for (final entry in _cityCoordinates.entries) {
      if (destClean.contains(entry.key)) return entry.value;
    }
    final coords = LocationService.getCityCoordinates(activeTrip.destination);
    return LatLng(coords[0], coords[1]);
  }

  LatLng _getStartingCoord(TripModel activeTrip) {
    if (activeTrip.startLat != null && activeTrip.startLng != null) {
      return LatLng(activeTrip.startLat!, activeTrip.startLng!);
    }
    if (_userLocation != null) return _userLocation!;
    final coords = LocationService.getCityCoordinates(activeTrip.startingPlace);
    return LatLng(coords[0], coords[1]);
  }

  Future<void> _calculateTripRoute() async {
    final activeTrip = ref.read(activeTripProvider);
    if (activeTrip == null) return;

    final start = _getStartingCoord(activeTrip);
    final dest = _getDestinationCoord(activeTrip);

    try {
      final route = await TripRouteService.calculateRoute(
        start: start,
        dest: dest,
        startName: activeTrip.startingPlace,
        destName: activeTrip.destination,
      );
      if (mounted) {
        setState(() {
          _tripRoute = route;
        });
      }
    } catch (_) {}
  }

  Future<void> _openDirections(LatLng target, String placeName) async {
    TripRouteService.launchGoogleMapsNavigation(
      destination: target,
      origin: _userLocation,
      destinationName: placeName,
    );
  }

  void _showPlaceDetails(
    String title,
    String subtitle,
    LatLng coords, {
    String? badgeText,
    Color badgeColor = const Color(0xFF258CF4),
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.place_rounded, color: badgeColor, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        if (subtitle.isNotEmpty)
                          Text(
                            subtitle,
                            style: const TextStyle(fontSize: 12, color: Colors.white70),
                          ),
                      ],
                    ),
                  ),
                  if (badgeText != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: badgeColor.withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        badgeText,
                        style: TextStyle(
                          color: badgeColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(Icons.gps_fixed_rounded, size: 14, color: Colors.white54),
                  const SizedBox(width: 6),
                  Text(
                    'GPS: ${coords.latitude.toStringAsFixed(4)}, ${coords.longitude.toStringAsFixed(4)}',
                    style: const TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                  if (_userLocation != null) ...[
                    const Spacer(),
                    Text(
                      '${(Geolocator.distanceBetween(_userLocation!.latitude, _userLocation!.longitude, coords.latitude, coords.longitude) / 1000.0).toStringAsFixed(1)} km away',
                      style: const TextStyle(color: Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF258CF4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.navigation_rounded, size: 18),
                  label: const Text('Start Navigation in Google Maps', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openDirections(coords, title);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTurnByTurnDirections(BuildContext context, TripRouteInfo route, TripModel activeTrip) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final bottomPadding = MediaQuery.of(ctx).padding.bottom;
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.35,
          maxChildSize: 0.90,
          expand: false,
          builder: (_, scrollController) {
            return SafeArea(
              top: false,
              bottom: true,
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottomPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Icon(Icons.directions_car_rounded, color: Color(0xFF258CF4), size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${activeTrip.startingPlace} → ${activeTrip.destination}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${route.distanceKm} km • ${route.durationFormatted} • ${route.summary}',
                      style: const TextStyle(color: Color(0xFF10B981), fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const Divider(color: Colors.white12, height: 24),
                    Expanded(
                      child: ListView.separated(
                        controller: scrollController,
                        itemCount: route.steps.length,
                        separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 16),
                        itemBuilder: (context, index) {
                          final step = route.steps[index];
                          final isFirst = index == 0;
                          final isLast = index == route.steps.length - 1;
                          final pinColor = isFirst
                              ? const Color(0xFF10B981)
                              : (isLast ? const Color(0xFFEF4444) : const Color(0xFF258CF4));

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: pinColor.withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '${index + 1}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: pinColor,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      step.instruction,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${step.distanceKm.toStringAsFixed(1)} km • ${step.durationFormatted}',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.5),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF258CF4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.navigation_rounded, size: 18),
                        label: const Text('Start Turn-by-Turn in Google Maps', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () {
                          Navigator.pop(ctx);
                          final destCoord = _getDestinationCoord(activeTrip);
                          _openDirections(destCoord, activeTrip.destination);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeTrip = ref.watch(activeTripProvider);
    final crewState = ref.watch(liveCrewProvider);

    if (activeTrip == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Trip Map & Routes')),
        body: const Center(child: Text('No active trip selected.')),
      );
    }

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text('${activeTrip.name} Map')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final destCoord = _getDestinationCoord(activeTrip);
    final startCoord = _getStartingCoord(activeTrip);

    // Route polyline points
    final polylinePoints = _tripRoute?.polylinePoints ?? [startCoord, destCoord];

    final markers = <Marker>[];

    // 1. Current user GPS Position marker
    if (_userLocation != null) {
      markers.add(
        Marker(
          point: _userLocation!,
          width: 52,
          height: 52,
          child: GestureDetector(
            onTap: () => _showPlaceDetails(
              'My Location',
              'Active GPS Position',
              _userLocation!,
              badgeText: 'You',
              badgeColor: const Color(0xFF10B981),
            ),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF258CF4).withValues(alpha: 0.25),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: const Color(0xFF258CF4),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // 2. Starting Point Origin Marker (if distinct from user location)
    if (_userLocation == null ||
        Geolocator.distanceBetween(
              _userLocation!.latitude,
              _userLocation!.longitude,
              startCoord.latitude,
              startCoord.longitude,
            ) >
            100) {
      markers.add(
        Marker(
          point: startCoord,
          width: 75,
          height: 60,
          child: GestureDetector(
            onTap: () => _showPlaceDetails(
              activeTrip.startingPlace,
              'Starting Point / Origin',
              startCoord,
              badgeText: 'Start',
              badgeColor: const Color(0xFF10B981),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                  ),
                  child: Text(
                    activeTrip.startingPlace,
                    style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.trip_origin_rounded, color: Color(0xFF10B981), size: 24),
              ],
            ),
          ),
        ),
      );
    }

    // 3. Destination Landmark Marker (Marina Beach / Trip Destination)
    markers.add(
      Marker(
        point: destCoord,
        width: 100,
        height: 70,
        child: GestureDetector(
          onTap: () => _showPlaceDetails(
            activeTrip.destination,
            'Verified Google Places Destination',
            destCoord,
            badgeText: 'Destination',
            badgeColor: const Color(0xFFEF4444),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
                ),
                child: Text(
                  activeTrip.destination.contains(',')
                      ? activeTrip.destination.split(',').first
                      : activeTrip.destination,
                  style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w900),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.location_on_rounded, color: Color(0xFFEF4444), size: 36),
            ],
          ),
        ),
      ),
    );

    // 4. GPS Location of Crew Members throughout the trip
    final currentUser = ref.read(authProvider).user;
    final currentUid = currentUser?.uid;

    final companionColors = [
      const Color(0xFFFF6B35),
      const Color(0xFF10B981),
      const Color(0xFF8B5CF6),
      const Color(0xFFF59E0B),
      const Color(0xFF06B6D4),
    ];

    // Render companions ONLY if they have valid real coordinates (live or pinned)
    for (int i = 0; i < crewState.members.length; i++) {
      final member = crewState.members[i];
      if (member.uid == currentUid) continue; // Current user is already rendered above

      LatLng? memberPos;
      String locationSource = 'Live GPS';

      if (member.latitude != null && member.longitude != null && !member.isExpired) {
        memberPos = LatLng(member.latitude!, member.longitude!);
      } else if (_chatPinnedLocations.containsKey(member.uid)) {
        final chatLoc = _chatPinnedLocations[member.uid]!;
        final lat = chatLoc['latitude'] as num?;
        final lng = chatLoc['longitude'] as num?;
        if (lat != null && lng != null) {
          memberPos = LatLng(lat.toDouble(), lng.toDouble());
          locationSource = 'Pinned in Chat';
        }
      }

      // DO NOT invent fake coordinates if member hasn't shared their location
      if (memberPos == null) continue;

      final companionName = member.displayName;
      final memberInitial = companionName.isNotEmpty ? companionName[0].toUpperCase() : 'M';
      final memberColor = companionColors[i % companionColors.length];

      markers.add(
        Marker(
          point: memberPos,
          width: 95,
          height: 70,
          child: GestureDetector(
            onTap: () => _showPlaceDetails(
              companionName,
              'Crew Member • $locationSource\nCoordinates: ${memberPos!.latitude.toStringAsFixed(4)}, ${memberPos.longitude.toStringAsFixed(4)}',
              memberPos,
              badgeText: locationSource,
              badgeColor: memberColor,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Name Tag
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: memberColor, width: 1.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: memberColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          companionName.split(' ').first,
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                // Avatar with radar halo
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: memberColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(color: memberColor.withValues(alpha: 0.5), blurRadius: 8, spreadRadius: 2),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      memberInitial,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          // Interactive OpenStreetMap Layer
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: destCoord,
              initialZoom: 13.5,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.tripcrew.travelapp',
              ),
              if (polylinePoints.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: polylinePoints,
                      strokeWidth: 5.0,
                      color: const Color(0xFF258CF4),
                    ),
                  ],
                ),
              MarkerLayer(markers: markers),
            ],
          ),

          // Floating Top Header
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Back Button
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.14),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.chevron_left_rounded,
                        color: Color(0xFF0F1E36),
                        size: 28,
                      ),
                    ),
                  ),

                  // Floating Title Tag
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.explore_rounded, size: 16, color: Color(0xFF258CF4)),
                        const SizedBox(width: 6),
                        Text(
                          '${activeTrip.name} Map',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F1E36),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Floating Notification Bell
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.14),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.notifications_none_rounded,
                      color: Color(0xFF0F1E36),
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Floating Map Controls (Right Side)
          Positioned(
            right: 16,
            top: 80,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'map_my_loc_btn',
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF0F1E36),
                  onPressed: () {
                    if (_userLocation != null) {
                      _mapController.move(_userLocation!, 15.0);
                    } else {
                      _checkUserLocation();
                    }
                  },
                  child: const Icon(Icons.my_location_rounded, size: 20),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'map_dest_loc_btn',
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFFEF4444),
                  tooltip: 'Go to Destination',
                  onPressed: () {
                    _mapController.move(destCoord, 14.5);
                  },
                  child: const Icon(Icons.location_on_rounded, size: 20),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'map_fit_route_btn',
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF258CF4),
                  tooltip: 'Fit Route',
                  onPressed: () {
                    final midLat = (startCoord.latitude + destCoord.latitude) / 2.0;
                    final midLng = (startCoord.longitude + destCoord.longitude) / 2.0;
                    _mapController.move(LatLng(midLat, midLng), 11.5);
                  },
                  child: const Icon(Icons.fit_screen_rounded, size: 20),
                ),
              ],
            ),
          ),

          // Properly Aligned Bottom Navigation Panel (Safe Area Aligned)
          Positioned(
            bottom: 20 + MediaQuery.of(context).padding.bottom,
            left: 14,
            right: 14,
            child: SafeArea(
              top: false,
              bottom: false,
              child: Card(
                elevation: 8,
                color: const Color(0xFF0F1E36),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: const BorderSide(color: Colors.white12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.alt_route_rounded, color: Color(0xFF258CF4), size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${activeTrip.startingPlace} → ${activeTrip.destination}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_tripRoute != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${_tripRoute!.distanceKm} km',
                                style: const TextStyle(
                                  color: Color(0xFF10B981),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          if (_tripRoute != null)
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: Colors.white24),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                icon: const Icon(Icons.format_list_bulleted_rounded, size: 16),
                                label: const Text('Directions', style: TextStyle(fontSize: 12)),
                                onPressed: () {
                                  _showTurnByTurnDirections(context, _tripRoute!, activeTrip);
                                },
                              ),
                            ),
                          if (_tripRoute != null) const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF258CF4),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: const Icon(Icons.navigation_rounded, size: 16),
                              label: const Text('Open in Maps', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              onPressed: () {
                                _openDirections(destCoord, activeTrip.destination);
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
