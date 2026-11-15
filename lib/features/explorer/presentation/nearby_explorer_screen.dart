import 'dart:developer' as developer;
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:tripcrew/app/theme.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/core/services/location_service.dart';
import 'package:tripcrew/core/services/supabase_service.dart';
import 'package:tripcrew/core/widgets/app_empty_state.dart';
import 'package:tripcrew/core/widgets/app_error_state.dart';
import 'package:tripcrew/features/auth/providers/auth_provider.dart';
import 'package:tripcrew/features/explorer/services/places_service.dart';
import 'package:tripcrew/features/trips/providers/trips_provider.dart';

class NearbyExplorerScreen extends ConsumerStatefulWidget {
  const NearbyExplorerScreen({super.key});

  @override
  ConsumerState<NearbyExplorerScreen> createState() =>
      _NearbyExplorerScreenState();
}

class _NearbyExplorerScreenState extends ConsumerState<NearbyExplorerScreen> {
  String _selectedCategory = 'All';
  final TextEditingController _searchCtrl = TextEditingController();
  List<NearbyPlace> _places = [];
  bool _isLoading = true;
  String? _errorMessage;
  String? _locationStatusBanner;
  Position? _currentPosition;
  String? _currentCity;

  // City coordinates fallback if GPS is unavailable
  static const Map<String, List<double>> _cityCoordinates = {
    'goa': [15.2993, 74.1240],
    'baga': [15.5524, 73.7517],
    'calangute': [15.5439, 73.7554],
    'panaji': [15.4909, 73.8278],
    'chennai': [13.0827, 80.2707],
    'pondy': [11.9416, 79.8083],
    'pondicherry': [11.9416, 79.8083],
    'bengaluru': [12.9716, 77.5946],
    'bangalore': [12.9716, 77.5946],
    'mumbai': [19.0760, 72.8777],
    'delhi': [28.6139, 77.2090],
    'manali': [32.2432, 77.1892],
    'jaipur': [26.9124, 75.7873],
  };

  @override
  void initState() {
    super.initState();
    _loadNearbyPlaces();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadNearbyPlaces() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    double lat = 13.0827; // Default Chennai/Tamil Nadu center
    double lon = 80.2707;

    final activeTrip = ref.read(activeTripProvider);

    // 1. Immediately check fast/cached location (<15ms)
    final fastLoc = await LocationService.getFastLocation();
    if (fastLoc != null && mounted) {
      lat = fastLoc.latitude;
      lon = fastLoc.longitude;
      _currentCity = fastLoc.city;
      _currentPosition = Position(
        latitude: fastLoc.latitude,
        longitude: fastLoc.longitude,
        timestamp: DateTime.now(),
        accuracy: 10,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
      _locationStatusBanner = null;
    }

    // 2. Fetch fresh, accurate position
    final freshLoc = await LocationService.getFreshLocation();
    if (freshLoc != null) {
      lat = freshLoc.latitude;
      lon = freshLoc.longitude;
      _currentCity = freshLoc.city;
      _currentPosition = Position(
        latitude: freshLoc.latitude,
        longitude: freshLoc.longitude,
        timestamp: DateTime.now(),
        accuracy: 10,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
      _locationStatusBanner = null;
    } else if (_currentPosition == null && activeTrip != null && activeTrip.destination.isNotEmpty) {
      final destClean = activeTrip.destination.toLowerCase().trim();
      for (final entry in _cityCoordinates.entries) {
        if (destClean.contains(entry.key)) {
          lat = entry.value[0];
          lon = entry.value[1];
          break;
        }
      }
      _locationStatusBanner = 'Showing places for trip destination (${activeTrip.destination}).';
    }

    final String resolvedCity = _currentCity ?? (activeTrip?.destination.isNotEmpty == true ? activeTrip!.destination : 'Local');

    try {
      final places = await PlacesService.fetchNearbyPlaces(
        latitude: lat,
        longitude: lon,
        categoryFilter: _selectedCategory == 'All' ? null : _selectedCategory,
        cityContext: resolvedCity,
      );

      if (places.isNotEmpty) {
        if (mounted) {
          setState(() {
            _places = places;
            _isLoading = false;
          });
        }
        return;
      }
    } catch (e) {
      developer.log('Failed fetching places: $e', name: 'NearbyExplorer');
    }

    // Curated contextual fallback based on user destination/current city
    final fallbackPlaces = PlacesService.generateContextualFallback(
      lat,
      lon,
      resolvedCity,
      _selectedCategory == 'All' ? null : _selectedCategory,
    );
    if (mounted) {
      setState(() {
        _places = fallbackPlaces;
        _isLoading = false;
      });
    }
  }

  Future<void> _openNavigation(NearbyPlace place) async {
    final double? uLat = _currentPosition?.latitude;
    final double? uLon = _currentPosition?.longitude;

    if (uLat != null && uLon != null) {
      final distance = Geolocator.distanceBetween(uLat, uLon, place.latitude, place.longitude);
      if (distance < 50) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('You are already at "${place.name}"!'),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
        }
        return;
      }
    }

    final placeQuery = Uri.encodeComponent(
      place.address != null && place.address!.isNotEmpty
          ? '${place.name}, ${place.address}'
          : place.name,
    );

    final navUri = Uri.parse(
      'google.navigation:q=${place.latitude},${place.longitude}&mode=d',
    );
    final googleMapsUrl = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${place.latitude},${place.longitude}&travelmode=driving',
    );
    final geoUrl = Uri.parse(
      'geo:${place.latitude},${place.longitude}?q=${place.latitude},${place.longitude}($placeQuery)',
    );

    try {
      if (Platform.isAndroid) {
        try {
          if (await canLaunchUrl(navUri)) {
            await launchUrl(navUri, mode: LaunchMode.externalApplication);
            return;
          }
        } catch (_) {}
      }

      try {
        if (await canLaunchUrl(googleMapsUrl)) {
          await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
          return;
        }
      } catch (_) {}

      try {
        if (await canLaunchUrl(geoUrl)) {
          await launchUrl(geoUrl, mode: LaunchMode.externalApplication);
          return;
        }
      } catch (_) {}

      await launchUrl(googleMapsUrl, mode: LaunchMode.platformDefault);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open map app: $e')),
        );
      }
    }
  }

  Future<void> _handleSearchDestination(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;

    final lower = q.toLowerCase();
    for (final entry in _cityCoordinates.entries) {
      if (lower.contains(entry.key)) {
        setState(() {
          _currentCity = entry.key[0].toUpperCase() + entry.key.substring(1);
          _currentPosition = Position(
            latitude: entry.value[0],
            longitude: entry.value[1],
            timestamp: DateTime.now(),
            accuracy: 10,
            altitude: 0,
            altitudeAccuracy: 0,
            heading: 0,
            headingAccuracy: 0,
            speed: 0,
            speedAccuracy: 0,
          );
        });
        await _loadNearbyPlaces();
        return;
      }
    }

    final searchUri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(q)}');
    try {
      await launchUrl(searchUri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _addToItinerary(NearbyPlace place) async {
    final activeTrip = ref.read(activeTripProvider);
    final user = ref.read(authProvider).user;
    if (activeTrip == null) return;

    if (SupabaseService.isInitialized) {
      try {
        final stopId = 'stop_${DateTime.now().millisecondsSinceEpoch}';
        await SupabaseService.client.from('itinerary_items').insert({
          'id': stopId,
          'trip_id': activeTrip.id,
          'title': place.name,
          'location': place.address ?? place.name,
          'day_number': 1,
          'time': '01:00 PM',
          'notes': place.cuisine != null ? 'Category: ${place.category} • ${place.cuisine}' : 'Added from Explorer',
          'is_completed': false,
          'latitude': place.latitude,
          'longitude': place.longitude,
          'order': 99,
          'created_by': user?.uid,
          'created_at': DateTime.now().toIso8601String(),
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Added "${place.name}" to trip itinerary!'),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to add to itinerary: $e')),
          );
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added "${place.name}" to local itinerary!')),
        );
      }
    }
  }

  Widget _buildPlaceFallbackBanner(NearbyPlace place, {double? height}) {
    List<Color> gradientColors;
    switch (place.category) {
      case 'Nature':
      case 'Park':
      case 'Lake':
      case 'Beach':
        gradientColors = const [Color(0xFF065F46), Color(0xFF059669)];
        break;
      case 'Heritage':
      case 'Historic':
        gradientColors = const [Color(0xFF78350F), Color(0xFFD97706)];
        break;
      case 'Transit':
      case 'Station':
        gradientColors = const [Color(0xFF1E3A8A), Color(0xFF2563EB)];
        break;
      case 'Cafes':
      case 'Coffee':
        gradientColors = const [Color(0xFF7C2D12), Color(0xFFEA580C)];
        break;
      case 'Food':
        gradientColors = const [Color(0xFF991B1B), Color(0xFFE11D48)];
        break;
      default:
        gradientColors = const [Color(0xFF0F1E36), Color(0xFF1E293B)];
    }

    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(place.icon, size: 28, color: Colors.white),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                place.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPlaceDetailsSheet(NearbyPlace place) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        top: false,
        child: Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              // Hero Photo Header
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                    child: (place.imageUrl != null && place.imageUrl!.isNotEmpty)
                        ? Image.network(
                            place.imageUrl!,
                            height: 220,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _buildPlaceFallbackBanner(place, height: 220),
                          )
                        : _buildPlaceFallbackBanner(place, height: 220),
                  ),
                // Close button top-left
                Positioned(
                  top: 16,
                  left: 16,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                    ),
                  ),
                ),
                // Route button top-right (Image 2 style)
                Positioned(
                  top: 16,
                  right: 16,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      _openNavigation(place);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.sand),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.near_me_rounded, color: AppTheme.espresso, size: 16),
                          SizedBox(width: 5),
                          Text(
                            'Route',
                            style: TextStyle(
                              color: AppTheme.espresso,
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Content Area
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppConstants.spaceLg),
                children: [
                  // Title & Star Rating
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          place.name,
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.espresso,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.warmBeige.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.sand),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 16),
                            const SizedBox(width: 4),
                            Text(
                              place.rating.toStringAsFixed(1),
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: AppTheme.espresso,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Meta Info Row (Location, Hours, Temp)
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetaBadge(
                          Icons.location_on_rounded,
                          'Address',
                          place.address ?? '${place.name}, ${_currentCity ?? "Local Area"}',
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildMetaBadge(
                        Icons.access_time_filled_rounded,
                        'Open',
                        place.status,
                      ),
                      const SizedBox(width: 8),
                      _buildMetaBadge(
                        Icons.wb_sunny_rounded,
                        'Temp',
                        '29°C',
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Tabs (Overview, Detail, Reviews)
                  Row(
                    children: [
                      _buildDetailTab('Overview', true),
                      const SizedBox(width: 16),
                      _buildDetailTab('Detail', false),
                      const SizedBox(width: 16),
                      _buildDetailTab('Reviews', false),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Description
                  Text(
                    '${place.name} is a premier destination in ${_currentCity ?? "the area"}. ${place.cuisine != null ? 'Renowned for ${place.cuisine!}, ' : ''}popular for authentic local sights, atmosphere, dining, and scenic exploration with your crew.',
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.55,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Direct Google & Web Resources
                  const Text(
                    'Google & Web Resources',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F1E36),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // Google Maps Navigation
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _openNavigation(place);
                        },
                        icon: const Icon(Icons.navigation_rounded, size: 16, color: Color(0xFF2563EB)),
                        label: const Text('Google Maps Route', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF2563EB),
                          side: const BorderSide(color: Color(0xFFBFDBFE)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      // Google Places & Live Reviews
                      OutlinedButton.icon(
                        onPressed: () async {
                          final query = Uri.encodeComponent('${place.name} ${place.address ?? _currentCity ?? ""} reviews ratings timings');
                          final url = Uri.parse('https://www.google.com/search?q=$query');
                          try {
                            await launchUrl(url, mode: LaunchMode.externalApplication);
                          } catch (_) {}
                        },
                        icon: const Icon(Icons.star_outline_rounded, size: 16, color: Color(0xFFF59E0B)),
                        label: const Text('Google Reviews & Timings', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFB45309),
                          side: const BorderSide(color: Color(0xFFFDE68A)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      // Web Resources & Official Guide
                      OutlinedButton.icon(
                        onPressed: () async {
                          final query = Uri.encodeComponent('${place.name} ${place.address ?? _currentCity ?? ""} official website tourism booking');
                          final url = Uri.parse('https://www.google.com/search?q=$query');
                          try {
                            await launchUrl(url, mode: LaunchMode.externalApplication);
                          } catch (_) {}
                        },
                        icon: const Icon(Icons.language_rounded, size: 16, color: Color(0xFF10B981)),
                        label: const Text('Web Search & Booking', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF047857),
                          side: const BorderSide(color: Color(0xFFA7F3D0)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),

            // Bottom Bar: Price + Book Now / Add to Itinerary
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Entry / Price:',
                          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.mocha),
                        ),
                        Text(
                          place.price ?? 'Free Entry',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.espresso,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.espresso,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 1,
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _addToItinerary(place);
                        },
                        child: Text(
                          'Book Now / Add to Trip',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

  Widget _buildMetaBadge(IconData icon, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.warmBeige.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.sand),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: AppTheme.caramel),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: GoogleFonts.inter(fontSize: 10, color: AppTheme.mocha, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.espresso),
            ),
          ],
        ),
      ),
    );
  }

  bool _matchesCategory(String placeCategory, String filter) {
    if (filter == 'All') return true;
    final f = filter.toLowerCase();
    final c = placeCategory.toLowerCase();
    if (f == c) return true;
    if ((f == 'restaurant' || f == 'food') && (c == 'restaurant' || c == 'food')) return true;
    if ((f == 'coffee' || f == 'cafes' || f == 'cafe') && (c == 'coffee' || c == 'cafes' || c == 'cafe')) return true;
    if ((f == 'hotel' || f == 'stays' || f == 'resort') && (c == 'hotel' || c == 'stays' || c == 'resort')) return true;
    if ((f == 'beach' || f == 'nature') && (c == 'beach' || c == 'nature' || c == 'park')) return true;
    if ((f == 'mountain' || f == 'nature') && (c == 'mountain' || c == 'nature' || c == 'viewpoint')) return true;
    if ((f == 'transit' || f == 'station') && (c == 'transit' || c == 'station')) return true;
    if ((f == 'museum' || f == 'heritage' || f == 'historic') && (c == 'museum' || c == 'heritage' || c == 'historic')) return true;
    if (f == 'atm' && c == 'atm') return true;
    return false;
  }

  Widget _buildDetailTab(String title, bool isActive) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
            color: isActive ? AppTheme.espresso : AppTheme.mocha,
          ),
        ),
        if (isActive)
          Container(
            margin: const EdgeInsets.only(top: 4),
            width: 20,
            height: 3,
            decoration: BoxDecoration(
              color: AppTheme.espresso,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeTrip = ref.watch(activeTripProvider);

    final searchQuery = _searchCtrl.text.toLowerCase().trim();
    final filtered = _places.where((p) {
      if (!_matchesCategory(p.category, _selectedCategory)) {
        return false;
      }
      if (searchQuery.isNotEmpty) {
        final matchesName = p.name.toLowerCase().contains(searchQuery);
        final matchesCuisine = p.cuisine?.toLowerCase().contains(searchQuery) ?? false;
        final matchesAddr = p.address?.toLowerCase().contains(searchQuery) ?? false;
        return matchesName || matchesCuisine || matchesAddr;
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: AppTheme.cream,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Top Bar with Location and Notification Bell
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 20, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        if (Navigator.canPop(context)) ...[
                          IconButton(
                            icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.espresso),
                            onPressed: () => Navigator.pop(context),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Explore Nearby',
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.espresso,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(
                                  Icons.location_on_rounded,
                                  color: AppTheme.terracotta,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _currentCity != null
                                      ? _currentCity!
                                      : (activeTrip?.destination.isNotEmpty == true
                                          ? activeTrip!.destination
                                          : 'Near You'),
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.mocha,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                    // Notification Bell with Badge Dot
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppTheme.sand),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.notifications_none_rounded,
                            color: AppTheme.espresso,
                            size: 20,
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppTheme.terracotta,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Location Status Banner if any
            if (_locationStatusBanner != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.warmBeige.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.sand),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, size: 16, color: AppTheme.terracotta),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _locationStatusBanner!,
                            style: GoogleFonts.inter(fontSize: 11.5, color: AppTheme.espresso, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Expressive Hero Headline & Travel Van Sticker
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Where You',
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.espresso,
                              height: 1.15,
                            ),
                          ),
                          Text(
                            'Wanna go?',
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.espresso,
                              height: 1.15,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Vacation Van Sticker Graphic
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.warmBeige,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppTheme.sand, width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.airport_shuttle_rounded,
                        color: AppTheme.espresso,
                        size: 34,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Search Bar with Circular Filter Button
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: AppTheme.sand, width: 1.2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search_rounded, color: AppTheme.mocha, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          textInputAction: TextInputAction.search,
                          onSubmitted: _handleSearchDestination,
                          onChanged: (_) => setState(() {}),
                          style: GoogleFonts.inter(
                            color: AppTheme.espresso,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search destination (e.g. Marina, Goa, Cafe)',
                            hintStyle: GoogleFonts.inter(color: AppTheme.mocha.withValues(alpha: 0.6), fontSize: 14),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      if (_searchCtrl.text.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _searchCtrl.clear();
                            setState(() {});
                          },
                          child: const Icon(Icons.clear_rounded, color: AppTheme.mocha, size: 18),
                        ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => _handleSearchDestination(_searchCtrl.text),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: const BoxDecoration(
                            color: AppTheme.espresso,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.search_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Promotions removed as requested - Clean spacing into Categories
            const SliverToBoxAdapter(child: SizedBox(height: 8)),

            // Category Chips Row (Image 2 style)
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Category',
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.espresso,
                          ),
                        ),
                        Text(
                          'See all',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.caramel,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      children: [
                        _buildCategoryPill('All', Icons.grid_view_rounded),
                        _buildCategoryPill('Beach', Icons.beach_access_rounded),
                        _buildCategoryPill('Mountain', Icons.terrain_rounded),
                        _buildCategoryPill('Coffee', Icons.local_cafe_rounded),
                        _buildCategoryPill('Restaurant', Icons.restaurant_rounded),
                        _buildCategoryPill('Hotel', Icons.hotel_rounded),
                        _buildCategoryPill('Transit', Icons.directions_bus_rounded),
                        _buildCategoryPill('ATM', Icons.credit_card_rounded),
                        _buildCategoryPill('Museum', Icons.museum_rounded),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 14)),

            // Destination Grid Cards
            if (_isLoading)
              const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(color: AppTheme.espresso),
                ),
              )
            else if (_errorMessage != null)
              SliverFillRemaining(
                child: AppErrorState(
                  title: 'Could Not Load Places',
                  message: _errorMessage!,
                  onRetry: _loadNearbyPlaces,
                ),
              )
            else if (filtered.isEmpty)
              SliverFillRemaining(
                child: AppEmptyState(
                  icon: Icons.search_off_rounded,
                  title: _searchCtrl.text.isNotEmpty
                      ? 'No local results for "${_searchCtrl.text}"'
                      : 'No places found',
                  message: _searchCtrl.text.isNotEmpty
                      ? 'Search Google Maps & Places to find exact addresses, live hours, and directions.'
                      : 'No ${_selectedCategory.toLowerCase()} places found nearby. Try another category or refresh location.',
                  actionLabel: _searchCtrl.text.isNotEmpty
                      ? 'Search "${_searchCtrl.text}" on Google Maps'
                      : 'Refresh Places',
                  onActionPressed: () {
                    if (_searchCtrl.text.isNotEmpty) {
                      _handleSearchDestination(_searchCtrl.text);
                    } else {
                      _loadNearbyPlaces();
                    }
                  },
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 140),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.78,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final place = filtered[index];
                      return _buildPlaceCard(place);
                    },
                    childCount: filtered.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryPill(String category, IconData icon) {
    final isSelected = _selectedCategory == category;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedCategory = category);
          _loadNearbyPlaces();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.espresso : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? AppTheme.espresso : AppTheme.sand,
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 4,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected ? Colors.white : AppTheme.mocha,
              ),
              const SizedBox(width: 6),
              Text(
                category,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : AppTheme.espresso,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceCard(NearbyPlace place) {
    return GestureDetector(
      onTap: () => _showPlaceDetailsSheet(place),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.sand, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Photo or Authentic Category Fallback Banner
              if (place.imageUrl != null && place.imageUrl!.isNotEmpty)
                Image.network(
                  place.imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _buildPlaceFallbackBanner(place),
                )
              else
                _buildPlaceFallbackBanner(place),

              // Gradient Scrim
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.08),
                      Colors.black.withValues(alpha: 0.75),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),

              // Top Bookmark/Heart Button
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.sand.withValues(alpha: 0.5)),
                  ),
                  child: const Icon(
                    Icons.favorite_rounded,
                    size: 16,
                    color: AppTheme.terracotta,
                  ),
                ),
              ),

              // Bottom Title, Location, and Rating
              Positioned(
                bottom: 12,
                left: 12,
                right: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      place.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            place.address ?? (place.distanceKm != null ? '${place.distanceKm} km away' : (_currentCity ?? 'Local Area')),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        // Star Rating Pill
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded, color: Color(0xFFFFD166), size: 14),
                            const SizedBox(width: 2),
                            Text(
                              place.rating.toStringAsFixed(1),
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
