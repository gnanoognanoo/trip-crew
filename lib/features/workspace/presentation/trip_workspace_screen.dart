import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tripcrew/app/theme.dart';
import 'package:tripcrew/core/services/destination_image_service.dart';
import 'package:tripcrew/core/services/supabase_service.dart';
import 'package:tripcrew/core/utils/currency_formatter.dart';
import 'package:tripcrew/features/itinerary/models/itinerary_item.dart';
import 'package:tripcrew/features/trips/models/trip_model.dart';
import 'package:tripcrew/features/trips/providers/trips_provider.dart';
import 'package:tripcrew/features/trips/services/trip_share_service.dart';

/// Screen for the dedicated per-trip INSIGHTS hub:
/// Displays ONLY:
/// 1. Authentic photos of that place from Google Places
/// 2. Budget of the trip (Total, Spent, Remaining)
/// 3. Timeline of the trip (Day-by-day Itinerary)
/// All extraneous module icons (itinerary, pay, chat, etc.) are removed as they are on the homepage.
class TripWorkspaceScreen extends ConsumerStatefulWidget {
  const TripWorkspaceScreen({super.key});

  @override
  ConsumerState<TripWorkspaceScreen> createState() => _TripWorkspaceScreenState();
}

class _TripWorkspaceScreenState extends ConsumerState<TripWorkspaceScreen> {
  String? _loadedPhotoUrl;
  List<String> _placesPhotos = [];
  List<ItineraryItem> _itineraryTimeline = [];
  bool _isLoadingTimeline = true;
  // ignore: unused_field
  List<String> _crewNames = [];
  String? _lastLoadedTripId;
  StreamSubscription? _itinerarySub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDetails();
    });
  }

  @override
  void dispose() {
    _itinerarySub?.cancel();
    super.dispose();
  }

  Future<void> _loadDetails() async {
    final trip = ref.read(activeTripProvider);
    if (trip == null) return;
    _lastLoadedTripId = trip.id;

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedCrew = prefs.getStringList('trip_crew_names_${trip.id}');
      if (savedCrew != null && savedCrew.isNotEmpty && mounted) {
        setState(() {
          _crewNames = savedCrew;
        });
      }
    } catch (_) {}

    try {
      final photo = await DestinationImageService.getDestinationPhoto(
        trip.destination,
        tripType: trip.tripType,
        coverPhotoUrl: trip.coverPhotoUrl,
      );
      if (mounted) {
        setState(() {
          _loadedPhotoUrl = photo;
        });
      }
    } catch (_) {}

    // Load authentic Google Places Photos
    try {
      final photos = await DestinationImageService.getDestinationPhotos(
        trip.destination,
        limit: 10,
      );
      if (mounted && photos.isNotEmpty) {
        setState(() {
          _placesPhotos = photos;
        });
      }
    } catch (_) {}

    // Load Itinerary Timeline from Supabase
    _listenToTimeline(trip.id);
  }

  void _listenToTimeline(String tripId) {
    if (SupabaseService.isInitialized) {
      try {
        _itinerarySub?.cancel();
        _itinerarySub = SupabaseService.client
            .from('itinerary_items')
            .stream(primaryKey: ['id'])
            .eq('trip_id', tripId)
            .listen(
              (data) {
                final loaded = data
                    .map((doc) => ItineraryItem.fromMap(
                          Map<String, dynamic>.from(doc),
                          doc['id'] as String,
                        ))
                    .toList();
                loaded.sort((a, b) {
                  final dayCmp = a.dayNumber.compareTo(b.dayNumber);
                  if (dayCmp != 0) return dayCmp;
                  final orderCmp = a.order.compareTo(b.order);
                  if (orderCmp != 0) return orderCmp;
                  return a.time.compareTo(b.time);
                });

                if (mounted) {
                  setState(() {
                    _itineraryTimeline = loaded;
                    _isLoadingTimeline = false;
                  });
                }
              },
              onError: (e) async {
                try {
                  final res = await SupabaseService.client
                      .from('itinerary_items')
                      .select()
                      .eq('trip_id', tripId)
                      .order('created_at', ascending: true);
                  final loaded = res
                      .map((doc) => ItineraryItem.fromMap(
                            Map<String, dynamic>.from(doc),
                            doc['id'] as String,
                          ))
                      .toList();
                  if (mounted) {
                    setState(() {
                      _itineraryTimeline = loaded;
                      _isLoadingTimeline = false;
                    });
                  }
                } catch (_) {
                  if (mounted) {
                    setState(() {
                      _isLoadingTimeline = false;
                    });
                  }
                }
              },
            );
        return;
      } catch (_) {}
    }
    if (mounted) {
      setState(() => _isLoadingTimeline = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final trip = ref.watch(activeTripProvider);

    if (trip != null && trip.id != _lastLoadedTripId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadDetails();
      });
    }

    if (trip == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            'Trip Insights',
            style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.w800),
          ),
        ),
        body: const Center(child: Text('No active trip selected.')),
      );
    }

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
        backgroundColor: isDark ? AppTheme.scaffoldDark : AppTheme.scaffoldLight,
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Trip Insights',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                trip.destination,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.copper,
                ),
              ),
            ],
          ),
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
          actions: [
            IconButton(
              icon: const Icon(Icons.share_rounded),
              tooltip: 'Share Trip',
              onPressed: () {
                TripShareService.showQrModal(
                  context,
                  inviteCode: trip.inviteCode,
                  tripName: trip.name,
                  tripId: trip.id,
                  startingPlace: trip.startingPlace,
                  destination: trip.destination,
                  startDate: trip.startDate,
                  endDate: trip.endDate,
                );
              },
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              tooltip: 'Trip Options',
              onSelected: (value) {
                if (value == 'edit') {
                  _showEditTripDialog(context, ref, trip);
                } else if (value == 'archive') {
                  _showArchiveTripDialog(context, ref, trip);
                } else if (value == 'delete') {
                  _showDeleteTripDialog(context, ref, trip);
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, size: 20),
                      SizedBox(width: 8),
                      Text('Edit Trip Details'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'archive',
                  child: Row(
                    children: [
                      Icon(
                        trip.status == 'completed'
                            ? Icons.unarchive_outlined
                            : Icons.archive_outlined,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        trip.status == 'completed'
                            ? 'Reactivate Trip'
                            : 'Mark as Completed',
                      ),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, size: 20, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Delete Trip', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // 1. Google Places Photos Section
              _buildGooglePlacesPhotosSection(context, trip, isDark),
              const SizedBox(height: 24),

              // 2. Budget of the Trip Section
              _buildTripBudgetSection(context, trip, isDark),
              const SizedBox(height: 24),

              // 3. Timeline of the Trip Section
              _buildTripTimelineSection(context, trip, isDark),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // 1. GOOGLE PLACES PHOTOS SECTION
  Widget _buildGooglePlacesPhotosSection(
    BuildContext context,
    TripModel trip,
    bool isDark,
  ) {
    final heroPhoto = _loadedPhotoUrl ??
        DestinationImageService.getQuickDestinationPhoto(
          trip.destination,
          tripType: trip.tripType,
          coverPhotoUrl: trip.coverPhotoUrl,
        );

    final photos = _placesPhotos.isNotEmpty
        ? _placesPhotos
        : [heroPhoto];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.photo_camera_rounded,
                  size: 20,
                  color: AppTheme.copper,
                ),
                const SizedBox(width: 8),
                Text(
                  'Google Places Photos',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : AppTheme.espressoBrown,
                  ),
                ),
              ],
            ),
            InkWell(
              onTap: () => _openDestinationGallery(context, trip),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  'View all (${photos.length}) ›',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.copper,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Hero Destination Banner with Warm Beige Scrim
        GestureDetector(
          onTap: () => _openDestinationGallery(context, trip),
          child: Container(
            height: 220,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.1),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  heroPhoto,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    decoration: const BoxDecoration(
                      gradient: AppTheme.tripSunsetGradient,
                    ),
                  ),
                ),
                // Warm beige overlay for natural travel photography tone
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.2),
                        const Color(0xFFE8DFD1).withValues(alpha: 0.15),
                        Colors.black.withValues(alpha: 0.8),
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
                // Place Name & Badge
                Positioned(
                  left: 16,
                  bottom: 16,
                  right: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.copper,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Google Places Verified',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        trip.destination,
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${trip.name} · ${trip.memberCount} Travelers',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Horizontal Carousel of Google Places Photos
        SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: photos.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (ctx, index) {
              final photo = photos[index];
              return GestureDetector(
                onTap: () => _openDestinationGallery(context, trip),
                child: Container(
                  width: 140,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark
                          ? AppTheme.espressoBorder
                          : AppTheme.warmBeige,
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.network(
                    photo,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: AppTheme.warmBeige,
                      child: const Center(
                        child: Icon(Icons.image_not_supported, color: Colors.grey),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // 2. BUDGET OF THE TRIP SECTION
  Widget _buildTripBudgetSection(
    BuildContext context,
    TripModel trip,
    bool isDark,
  ) {
    final double totalBudget = trip.budget > 0 ? trip.budget : 10000;
    final double spentUnits = (trip.totalSpendingPaise > 0)
        ? (trip.totalSpendingPaise / 100.0)
        : 0.0;
    final double remaining = totalBudget - spentUnits;
    final double progress = (totalBudget > 0)
        ? (spentUnits / totalBudget).clamp(0.0, 1.0)
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Row(
          children: [
            const Icon(
              Icons.account_balance_wallet_rounded,
              size: 20,
              color: AppTheme.copper,
            ),
            const SizedBox(width: 8),
            Text(
              'Trip Budget',
              style: GoogleFonts.playfairDisplay(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : AppTheme.espressoBrown,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Budget Card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.espressoSurface : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? AppTheme.espressoBorder : AppTheme.warmBeige,
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Allocated Budget',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        CurrencyFormatter.format(totalBudget),
                        style: GoogleFonts.inter(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: isDark ? Colors.white : AppTheme.espressoBrown,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.copper.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${(progress * 100).toStringAsFixed(0)}% Used',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.copper,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Progress Bar
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: isDark
                      ? Colors.white12
                      : AppTheme.warmBeige,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.copper),
                ),
              ),
              const SizedBox(height: 14),

              // Spent vs Remaining breakdown
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppTheme.espressoCard
                            : AppTheme.warmBeigeLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark
                              ? AppTheme.espressoBorder
                              : AppTheme.warmBeige,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFEF4444),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Spent',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white70 : Colors.black54,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            CurrencyFormatter.format(spentUnits),
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.white : AppTheme.espressoBrown,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppTheme.espressoCard
                            : AppTheme.warmBeigeLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark
                              ? AppTheme.espressoBorder
                              : AppTheme.warmBeige,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF10B981),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Remaining',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white70 : Colors.black54,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            CurrencyFormatter.format(remaining > 0 ? remaining : 0),
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF10B981),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 3. TIMELINE OF THE TRIP SECTION
  Widget _buildTripTimelineSection(
    BuildContext context,
    TripModel trip,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.timeline_rounded,
                  size: 20,
                  color: AppTheme.copper,
                ),
                const SizedBox(width: 8),
                Text(
                  'Trip Timeline',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : AppTheme.espressoBrown,
                  ),
                ),
              ],
            ),
            Text(
              '${DateFormat('d MMM').format(trip.startDate)} - ${DateFormat('d MMM').format(trip.endDate)}',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (_isLoadingTimeline)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(color: AppTheme.copper),
            ),
          )
        else if (_itineraryTimeline.isNotEmpty)
          ..._buildGroupedTimelineWidgets(context, _itineraryTimeline, isDark)
        else
          // Clean default timeline based on trip destination and dates
          _buildDefaultTimelineCard(context, trip, isDark),
      ],
    );
  }

  List<Widget> _buildGroupedTimelineWidgets(
    BuildContext context,
    List<ItineraryItem> items,
    bool isDark,
  ) {
    final Map<int, List<ItineraryItem>> byDay = {};
    for (final item in items) {
      byDay.putIfAbsent(item.dayNumber, () => []).add(item);
    }

    final sortedDays = byDay.keys.toList()..sort();
    final widgets = <Widget>[];

    for (final day in sortedDays) {
      final dayItems = byDay[day]!;
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.copper,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Day $day',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Divider(
                  color: isDark ? AppTheme.espressoBorder : AppTheme.warmBeige,
                  thickness: 1,
                ),
              ),
            ],
          ),
        ),
      );

      for (int i = 0; i < dayItems.length; i++) {
        final stop = dayItems[i];
        // index: $i

        widgets.add(
          Container(
            margin: const EdgeInsets.only(left: 8, bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.espressoSurface : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? AppTheme.espressoBorder : AppTheme.warmBeige,
                width: 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.copper.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.location_on_rounded,
                    size: 16,
                    color: AppTheme.copper,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              stop.title,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: isDark ? Colors.white : AppTheme.espressoBrown,
                              ),
                            ),
                          ),
                          if (stop.time.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white10 : AppTheme.warmBeigeLight,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                stop.time,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.copper,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (stop.notes != null && stop.notes!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          stop.notes!,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    return widgets;
  }

  Widget _buildDefaultTimelineCard(
    BuildContext context,
    TripModel trip,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.espressoSurface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? AppTheme.espressoBorder : AppTheme.warmBeige,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.copper,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Day 1 - Arrival',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Kick-off & Exploration',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: isDark ? Colors.white70 : AppTheme.espressoBrown,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Welcome to ${trip.destination}! Check into accommodations, meet up with crew members, and take in the golden sunset vistas along the promenade.',
            style: GoogleFonts.inter(
              fontSize: 12.5,
              height: 1.4,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.copper.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Day 2 - Adventure',
                  style: GoogleFonts.inter(
                    color: AppTheme.copper,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Landmarks & Local Flavors',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: isDark ? Colors.white70 : AppTheme.espressoBrown,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Explore iconic heritage spots, coastal seafood dining, and memorable photography spots across ${trip.destination}.',
            style: GoogleFonts.inter(
              fontSize: 12.5,
              height: 1.4,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  void _openDestinationGallery(BuildContext context, TripModel trip) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1B0F0A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollCtrl) {
            return FutureBuilder<List<String>>(
              future: DestinationImageService.getDestinationPhotos(trip.destination, limit: 10),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppTheme.copper),
                  );
                }
                final photos = snapshot.data ?? [];
                if (photos.isEmpty) {
                  return const Center(
                    child: Text('No Google Places photos available.', style: TextStyle(color: Colors.white70)),
                  );
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                          const Icon(Icons.place_rounded, color: AppTheme.copper, size: 20),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Google Places: ${trip.destination}',
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Authentic Google Places photos of this destination. Tap to set as trip cover.',
                        style: GoogleFonts.inter(fontSize: 12, color: Colors.white60),
                      ),
                      const SizedBox(height: 14),
                      Expanded(
                        child: GridView.builder(
                          controller: scrollCtrl,
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: 1.1,
                          ),
                          itemCount: photos.length,
                          itemBuilder: (context, idx) {
                            final pUrl = photos[idx];
                            return GestureDetector(
                              onTap: () async {
                                Navigator.pop(ctx);
                                try {
                                  if (SupabaseService.isInitialized) {
                                    await SupabaseService.client
                                        .from('trips')
                                        .update({'cover_photo_url': pUrl})
                                        .eq('id', trip.id);
                                  }
                                  final prefs = await SharedPreferences.getInstance();
                                  await prefs.setString('trip_cover_photo_${trip.id}', pUrl);
                                  setState(() {
                                    _loadedPhotoUrl = pUrl;
                                  });
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Trip cover photo updated from Google Places!'),
                                        backgroundColor: Color(0xFF10B981),
                                      ),
                                    );
                                  }
                                } catch (_) {}
                              },
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.network(
                                      pUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        color: AppTheme.espressoSurface,
                                        child: const Icon(Icons.broken_image, color: Colors.white30),
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 6,
                                      right: 6,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.6),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.check, size: 14, color: Colors.white),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _showEditTripDialog(
    BuildContext context,
    WidgetRef ref,
    TripModel trip,
  ) {
    final nameController = TextEditingController(text: trip.name);
    final destinationController = TextEditingController(text: trip.destination);
    final budgetController = TextEditingController(text: trip.budget.toStringAsFixed(0));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Trip Details', style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Trip Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: destinationController,
                decoration: const InputDecoration(labelText: 'Destination'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: budgetController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Budget (INR)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.copper),
            onPressed: () async {
              final newName = nameController.text.trim();
              final newDest = destinationController.text.trim();
              final newBudget = double.tryParse(budgetController.text.trim()) ?? trip.budget;

              if (newName.isNotEmpty && newDest.isNotEmpty) {
                Navigator.pop(ctx);
                await ref.read(tripsProvider.notifier).updateTrip(
                  tripId: trip.id,
                  name: newName,
                  destination: newDest,
                  budget: newBudget,
                );
                if (mounted) setState(() {});
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showArchiveTripDialog(
    BuildContext context,
    WidgetRef ref,
    TripModel trip,
  ) {
    final isCompleted = trip.status == 'completed';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isCompleted ? 'Reactivate Trip' : 'Mark as Completed'),
        content: Text(
          isCompleted
              ? 'Do you want to reactivate "${trip.name}"?'
              : 'Are you sure you want to conclude "${trip.name}" as carried out?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.copper),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(tripsProvider.notifier).setTripStatus(
                tripId: trip.id,
                status: isCompleted ? 'upcoming' : 'completed',
              );
            },
            child: Text(isCompleted ? 'Reactivate' : 'Complete'),
          ),
        ],
      ),
    );
  }

  void _showDeleteTripDialog(
    BuildContext context,
    WidgetRef ref,
    TripModel trip,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Trip', style: TextStyle(color: Colors.red)),
        content: Text('Are you sure you want to permanently delete "${trip.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(tripsProvider.notifier).deleteTrip(trip.id);
              if (context.mounted) {
                context.go('/');
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
