import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/core/services/destination_image_service.dart';
import 'package:tripcrew/core/services/location_service.dart';
import 'package:tripcrew/core/services/trip_route_service.dart';
import 'package:tripcrew/features/trips/providers/trips_provider.dart';

/// Screen 4: Create a Trip with Google Maps location/address linking,
/// authentic destination placeholder imagery, and live route viewer with directions.
class CreateTripScreen extends ConsumerStatefulWidget {
  const CreateTripScreen({super.key});

  @override
  ConsumerState<CreateTripScreen> createState() => _CreateTripScreenState();
}

class _CreateTripScreenState extends ConsumerState<CreateTripScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _startingPlaceController = TextEditingController();
  final _destinationController = TextEditingController();
  final _budgetController = TextEditingController();

  DateTime _startDate = DateTime.now().add(const Duration(days: 7));
  DateTime _endDate = DateTime.now().add(const Duration(days: 10));
  String _selectedTripType = 'Road Trip';
  String _selectedCurrency = 'INR (₹)';
  bool _isSubmitting = false;

  // Google Maps address linking & suggestions state
  Timer? _destDebounceTimer;
  Timer? _startDebounceTimer;
  bool _isSearchingDest = false;
  bool _isSearchingStart = false;
  List<DestinationPlaceInfo> _startSuggestions = [];
  List<DestinationPlaceInfo> _destSuggestions = [];
  DestinationPlaceInfo? _resolvedStart;
  DestinationPlaceInfo? _resolvedDest;

  // Route & Directions state
  final MapController _routeMapController = MapController();
  TripRouteInfo? _routeInfo;
  bool _isCalculatingRoute = false;

  final List<String> _tripTypes = [
    'Road Trip',
    'Vacation',
    'Family',
    'Adventure',
    'Trek',
  ];

  @override
  void initState() {
    super.initState();
    _startingPlaceController.addListener(_onStartPlaceChanged);
    _destinationController.addListener(_onDestinationChanged);
  }

  @override
  void dispose() {
    _startDebounceTimer?.cancel();
    _destDebounceTimer?.cancel();
    _startingPlaceController.removeListener(_onStartPlaceChanged);
    _destinationController.removeListener(_onDestinationChanged);
    _nameController.dispose();
    _startingPlaceController.dispose();
    _destinationController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  // --- Starting Place Autocomplete & GPS ---
  void _onStartPlaceChanged() {
    final text = _startingPlaceController.text.trim();
    if (text.isEmpty) {
      if (_startSuggestions.isNotEmpty || _resolvedStart != null) {
        setState(() {
          _startSuggestions = [];
          _resolvedStart = null;
          _routeInfo = null;
        });
      }
      return;
    }
    _startDebounceTimer?.cancel();
    _startDebounceTimer = Timer(const Duration(milliseconds: 450), () {
      _lookupStartSuggestions(text);
    });
  }

  Future<void> _lookupStartSuggestions(String query) async {
    if (!mounted) return;
    setState(() => _isSearchingStart = true);
    try {
      final list = await DestinationImageService.searchPlaceSuggestions(query, limit: 4);
      if (mounted) {
        setState(() {
          _startSuggestions = list;
          _isSearchingStart = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isSearchingStart = false);
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _isSearchingStart = true);
    try {
      final loc = await LocationService.getFreshLocation();
      if (loc != null && mounted) {
        final addressStr = '${loc.city}, ${loc.country}';
        final placeInfo = DestinationPlaceInfo(
          photoUrl: DestinationImageService.getQuickDestinationPhoto(loc.city),
          placeName: loc.city,
          address: addressStr,
          latitude: loc.latitude,
          longitude: loc.longitude,
        );
        setState(() {
          _resolvedStart = placeInfo;
          _startingPlaceController.text = addressStr;
          _startSuggestions = [];
          _isSearchingStart = false;
        });
        _triggerRouteRecalculation();
      } else {
        if (mounted) setState(() => _isSearchingStart = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isSearchingStart = false);
    }
  }

  void _selectStartSuggestion(DestinationPlaceInfo info) {
    setState(() {
      _resolvedStart = info;
      _startingPlaceController.text = info.address ?? info.placeName;
      _startSuggestions = [];
    });
    _triggerRouteRecalculation();
  }

  // --- Destination Autocomplete & Photo Linking ---
  void _onDestinationChanged() {
    final text = _destinationController.text.trim();
    if (text.isEmpty) {
      if (_destSuggestions.isNotEmpty || _resolvedDest != null) {
        setState(() {
          _destSuggestions = [];
          _resolvedDest = null;
          _routeInfo = null;
        });
      }
      return;
    }
    _destDebounceTimer?.cancel();
    _destDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      _lookupDestSuggestions(text);
    });
  }

  Future<void> _lookupDestSuggestions(String query) async {
    if (!mounted) return;
    setState(() => _isSearchingDest = true);
    try {
      final list = await DestinationImageService.searchPlaceSuggestions(query, limit: 4);
      final single = await DestinationImageService.searchPlace(query, tripType: _selectedTripType);
      if (mounted) {
        setState(() {
          _destSuggestions = list;
          _resolvedDest = single;
          _isSearchingDest = false;
        });
        _triggerRouteRecalculation();
      }
    } catch (_) {
      if (mounted) setState(() => _isSearchingDest = false);
    }
  }

  void _selectDestSuggestion(DestinationPlaceInfo info) {
    setState(() {
      _resolvedDest = info;
      _destinationController.text = info.address ?? info.placeName;
      _destSuggestions = [];
    });
    _triggerRouteRecalculation();
  }

  // --- Route & Directions Computation ---
  Future<void> _triggerRouteRecalculation() async {
    final sText = _startingPlaceController.text.trim();
    final dText = _destinationController.text.trim();
    if (sText.isEmpty || dText.isEmpty) return;

    // Resolve start coordinates
    LatLng startCoord;
    if (_resolvedStart?.latitude != null && _resolvedStart?.longitude != null) {
      startCoord = LatLng(_resolvedStart!.latitude!, _resolvedStart!.longitude!);
    } else {
      final coords = LocationService.getCityCoordinates(sText);
      startCoord = LatLng(coords[0], coords[1]);
    }

    // Resolve destination coordinates
    LatLng destCoord;
    if (_resolvedDest?.latitude != null && _resolvedDest?.longitude != null) {
      destCoord = LatLng(_resolvedDest!.latitude!, _resolvedDest!.longitude!);
    } else {
      final coords = LocationService.getCityCoordinates(dText);
      destCoord = LatLng(coords[0], coords[1]);
    }

    setState(() => _isCalculatingRoute = true);

    try {
      final route = await TripRouteService.calculateRoute(
        start: startCoord,
        dest: destCoord,
        startName: _resolvedStart?.placeName ?? sText,
        destName: _resolvedDest?.placeName ?? dText,
      );

      if (mounted) {
        setState(() {
          _routeInfo = route;
          _isCalculatingRoute = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isCalculatingRoute = false);
    }
  }

  void _launchMapsNavigation() {
    final sText = _startingPlaceController.text.trim();
    final dText = _destinationController.text.trim();
    if (dText.isEmpty) return;

    LatLng? startCoord;
    if (_resolvedStart?.latitude != null && _resolvedStart?.longitude != null) {
      startCoord = LatLng(_resolvedStart!.latitude!, _resolvedStart!.longitude!);
    } else if (sText.isNotEmpty) {
      final coords = LocationService.getCityCoordinates(sText);
      startCoord = LatLng(coords[0], coords[1]);
    }

    LatLng destCoord;
    if (_resolvedDest?.latitude != null && _resolvedDest?.longitude != null) {
      destCoord = LatLng(_resolvedDest!.latitude!, _resolvedDest!.longitude!);
    } else {
      final coords = LocationService.getCityCoordinates(dText);
      destCoord = LatLng(coords[0], coords[1]);
    }

    TripRouteService.launchGoogleMapsNavigation(
      destination: destCoord,
      origin: startCoord,
      destinationName: _resolvedDest?.placeName ?? dText,
    );
  }

  void _showDirectionsModal(BuildContext context, TripRouteInfo route) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.35,
          maxChildSize: 0.88,
          expand: false,
          builder: (_, scrollController) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                          '${_startingPlaceController.text} → ${_destinationController.text}',
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
                  SafeArea(
                    top: false,
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF258CF4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.navigation_rounded, size: 18),
                        label: const Text(
                          'Start Turn-by-Turn in Google Maps',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _launchMapsNavigation();
                        },
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  double _calculateZoom(double distanceKm) {
    if (distanceKm > 1000) return 4.5;
    if (distanceKm > 500) return 5.5;
    if (distanceKm > 250) return 6.8;
    if (distanceKm > 100) return 7.8;
    if (distanceKm > 40) return 9.2;
    if (distanceKm > 15) return 10.8;
    return 12.0;
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_endDate.isBefore(_startDate)) {
            _endDate = _startDate.add(const Duration(days: 3));
          }
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _handleCreateTrip() async {
    if (_isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      final budgetVal = double.tryParse(_budgetController.text.trim()) ?? 2500.0;
      final trip = await ref.read(tripsProvider.notifier).createTrip(
            name: _nameController.text,
            startingPlace: _startingPlaceController.text,
            destination: _destinationController.text,
            startDate: _startDate,
            endDate: _endDate,
            tripType: _selectedTripType,
            budget: budgetVal,
            currency: _selectedCurrency,
            coverPhotoUrl: _resolvedDest?.photoUrl,
            startLat: _resolvedStart?.latitude,
            startLng: _resolvedStart?.longitude,
            destLat: _resolvedDest?.latitude,
            destLng: _resolvedDest?.longitude,
            startingPlaceAddress: _resolvedStart?.address,
            destinationAddress: _resolvedDest?.address,
          );

      if (mounted) {
        context.pushReplacement('/trip-created', extra: trip);
      }
    } catch (e) {
      if (mounted) {
        String friendlyMessage = "We couldn't create your trip. Please try again.";
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyMessage)));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/');
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Create a Trip'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/');
              }
            },
          ),
        ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceLg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppConstants.spaceMd),

                // Trip Name
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Trip Name',
                    hintText: 'e.g. Pondicherry Road Trip',
                  ),
                  validator: (val) =>
                      val == null || val.trim().isEmpty ? 'Trip name is required' : null,
                ),
                const SizedBox(height: AppConstants.spaceMd),

                // Starting Place (with GPS & Google Maps Suggestions)
                TextFormField(
                  controller: _startingPlaceController,
                  decoration: InputDecoration(
                    labelText: 'Starting Place',
                    hintText: 'e.g. Avadi, Chennai',
                    prefixIcon: const Icon(Icons.trip_origin_rounded, color: Color(0xFF10B981)),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.my_location_rounded, color: Color(0xFF258CF4)),
                      tooltip: 'Use current GPS location',
                      onPressed: _useCurrentLocation,
                    ),
                  ),
                  validator: (val) =>
                      val == null || val.trim().isEmpty ? 'Starting place is required' : null,
                ),

                // Starting Place Suggestions Dropdown
                if (_isSearchingStart) ...[
                  const SizedBox(height: 6),
                  const LinearProgressIndicator(minHeight: 2),
                ] else if (_startSuggestions.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      children: _startSuggestions.map((info) {
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.place_outlined, size: 18, color: Color(0xFF10B981)),
                          title: Text(info.placeName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                          subtitle: info.address != null
                              ? Text(info.address!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.white60))
                              : null,
                          onTap: () => _selectStartSuggestion(info),
                        );
                      }).toList(),
                    ),
                  ),
                ],

                // Starting Place Linked Address Badge
                if (_resolvedStart?.address != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Linked Origin: ${_resolvedStart!.address}',
                          style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppConstants.spaceMd),

                // Destination (with Google Maps Suggestions & Photo Linking)
                TextFormField(
                  controller: _destinationController,
                  decoration: const InputDecoration(
                    labelText: 'Destination',
                    hintText: 'e.g. Pondicherry',
                    prefixIcon: Icon(Icons.location_on_rounded, color: Color(0xFFEF4444)),
                  ),
                  validator: (val) =>
                      val == null || val.trim().isEmpty ? 'Destination is required' : null,
                ),

                // Destination Suggestions Dropdown
                if (_isSearchingDest) ...[
                  const SizedBox(height: 6),
                  const LinearProgressIndicator(minHeight: 2),
                ] else if (_destSuggestions.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      children: _destSuggestions.map((info) {
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.place_outlined, size: 18, color: Color(0xFFEF4444)),
                          title: Text(info.placeName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                          subtitle: info.address != null
                              ? Text(info.address!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.white60))
                              : null,
                          onTap: () => _selectDestSuggestion(info),
                        );
                      }).toList(),
                    ),
                  ),
                ],

                // Google Maps Verified Destination Photo Card
                if (_resolvedDest != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Stack(
                          children: [
                            Image.network(
                              _resolvedDest!.photoUrl,
                              height: 130,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                height: 130,
                                color: Colors.black26,
                                child: const Center(
                                  child: Icon(Icons.broken_image_rounded, color: Colors.white38),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.75),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 12),
                                    SizedBox(width: 4),
                                    Text(
                                      'Google Places Photo',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              const Icon(Icons.place_rounded, color: Color(0xFFEF4444), size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _resolvedDest!.placeName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    if (_resolvedDest!.address != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        _resolvedDest!.address!,
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.65),
                                          fontSize: 11,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.refresh_rounded, size: 18, color: Colors.white70),
                                tooltip: 'Refresh photo from Google Places',
                                onPressed: () => _lookupDestSuggestions(_destinationController.text.trim()),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppConstants.spaceMd),

                // --- LIVE ROUTE VIEWER & DIRECTIONS PREVIEW ---
                if (_isCalculatingRoute) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: const Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF258CF4)),
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Calculating driving route & directions...',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppConstants.spaceMd),
                ] else if (_routeInfo != null) ...[
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF258CF4).withValues(alpha: 0.4)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Route Header
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              const Icon(Icons.alt_route_rounded, color: Color(0xFF258CF4), size: 20),
                              const SizedBox(width: 8),
                              const Text(
                                'Route & Navigation Preview',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF258CF4).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFF258CF4).withValues(alpha: 0.4)),
                                ),
                                child: Text(
                                  '${_routeInfo!.distanceKm} km • ${_routeInfo!.durationFormatted}',
                                  style: const TextStyle(
                                    color: Color(0xFF258CF4),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Interactive Route Map
                        SizedBox(
                          height: 180,
                          child: Builder(
                            builder: (context) {
                              final startPoint = _routeInfo!.polylinePoints.first;
                              final endPoint = _routeInfo!.polylinePoints.last;
                              final midPoint = LatLng(
                                (startPoint.latitude + endPoint.latitude) / 2.0,
                                (startPoint.longitude + endPoint.longitude) / 2.0,
                              );
                              final zoom = _calculateZoom(_routeInfo!.distanceKm);

                              return FlutterMap(
                                mapController: _routeMapController,
                                options: MapOptions(
                                  initialCenter: midPoint,
                                  initialZoom: zoom,
                                  interactionOptions: const InteractionOptions(
                                    flags: InteractiveFlag.all,
                                  ),
                                ),
                                children: [
                                  TileLayer(
                                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                    userAgentPackageName: 'com.tripcrew.travelapp',
                                  ),
                                  PolylineLayer(
                                    polylines: [
                                      Polyline(
                                        points: _routeInfo!.polylinePoints,
                                        strokeWidth: 4.5,
                                        color: const Color(0xFF258CF4),
                                      ),
                                    ],
                                  ),
                                  MarkerLayer(
                                    markers: [
                                      Marker(
                                        point: startPoint,
                                        width: 32,
                                        height: 32,
                                        child: const Icon(
                                          Icons.trip_origin_rounded,
                                          color: Color(0xFF10B981),
                                          size: 28,
                                        ),
                                      ),
                                      Marker(
                                        point: endPoint,
                                        width: 32,
                                        height: 32,
                                        child: const Icon(
                                          Icons.location_on_rounded,
                                          color: Color(0xFFEF4444),
                                          size: 32,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            },
                          ),
                        ),

                        // Route Action Buttons
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: const BorderSide(color: Colors.white24),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                  ),
                                  icon: const Icon(Icons.format_list_bulleted_rounded, size: 16),
                                  label: Text(
                                    'Directions (${_routeInfo!.steps.length})',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  onPressed: () => _showDirectionsModal(context, _routeInfo!),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF258CF4),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                  ),
                                  icon: const Icon(Icons.navigation_rounded, size: 16),
                                  label: const Text(
                                    'Open in Maps',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  onPressed: _launchMapsNavigation,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppConstants.spaceMd),
                ],

                // Dates Row
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _pickDate(isStart: true),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Start Date',
                            suffixIcon: Icon(Icons.calendar_today, size: 18),
                          ),
                          child: Text(
                            dateFormat.format(_startDate),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppConstants.spaceSm),
                    Expanded(
                      child: InkWell(
                        onTap: () => _pickDate(isStart: false),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'End Date',
                            suffixIcon: Icon(Icons.calendar_today, size: 18),
                          ),
                          child: Text(
                            dateFormat.format(_endDate),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppConstants.spaceLg),

                // Trip Type
                const Text(
                  'Trip Type',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: AppConstants.spaceSm),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _tripTypes.map((type) {
                    final isSelected = _selectedTripType == type;
                    return ChoiceChip(
                      label: Text(type),
                      selected: isSelected,
                      onSelected: (val) {
                        setState(() => _selectedTripType = type);
                        _triggerRouteRecalculation();
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: AppConstants.spaceLg),

                // Budget and Currency
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _budgetController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Budget',
                          hintText: 'e.g. 2500',
                        ),
                        validator: (val) => val == null || val.trim().isEmpty
                            ? 'Enter budget'
                            : null,
                      ),
                    ),
                    const SizedBox(width: AppConstants.spaceSm),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedCurrency,
                        decoration: const InputDecoration(
                          labelText: 'Currency',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'INR (₹)',
                            child: Text('INR (₹)'),
                          ),
                          DropdownMenuItem(
                            value: 'USD (\$)',
                            child: Text('USD (\$)'),
                          ),
                          DropdownMenuItem(
                            value: 'EUR (€)',
                            child: Text('EUR (€)'),
                          ),
                        ],
                        onChanged: (val) => setState(() => _selectedCurrency = val!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppConstants.space2xl),

                // Create Trip Button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isSubmitting ? null : _handleCreateTrip,
                    child: _isSubmitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Create Trip'),
                  ),
                ),
                const SizedBox(height: AppConstants.spaceLg),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}
