import 'package:tripcrew/app/theme.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/core/services/location_service.dart';
import 'package:tripcrew/core/services/supabase_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tripcrew/features/auth/providers/auth_provider.dart';
import 'package:tripcrew/features/explorer/services/places_service.dart';
import 'package:tripcrew/features/itinerary/models/itinerary_item.dart';
import 'package:tripcrew/features/trips/models/trip_model.dart';
import 'package:tripcrew/features/trips/providers/trips_provider.dart';
import 'package:tripcrew/features/trips/services/trip_share_service.dart';
import 'package:tripcrew/features/ai/presentation/ai_assistant_dialog.dart';
import 'package:tripcrew/core/services/trip_notification_watcher.dart';
import 'package:url_launcher/url_launcher.dart';

class _CrewNotification {
  final String id;
  final String title;
  final String subtitle;
  final String timeAgo;
  final IconData icon;
  final Color iconColor;
  final String route;

  const _CrewNotification({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.timeAgo,
    required this.icon,
    required this.iconColor,
    required this.route,
  });
}

class _CompanionEntry {
  final TextEditingController controller;
  final String? userId;
  final bool isOrganizer;

  _CompanionEntry({
    required this.controller,
    this.userId,
    this.isOrganizer = false,
  });
}

/// Screen 3: Home Dashboard matching the startup UI mockup with Field Notes aesthetic.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _scrollVelocity = ValueNotifier<double>(0);
  DateTime? _lastScrollAt;
  double _lastScrollPixels = 0;
  Timer? _velocityDecay;

  // ignore: unused_field
  List<ItineraryItem> _upcomingItinerary = [];
  // ignore: unused_field
  String? _crewActivityText;
  String? _lastLoadedTripId;
  StreamSubscription<List<Map<String, dynamic>>>? _itinerarySub;
  List<_CrewNotification> _crewNotifications = [];
  StreamSubscription? _notificationWatcherSub;
  List<String> _tripCrewNames = [];
  final Map<String, String> _tripStatusOverrides = {};
  String? _cachedUserName;
  Timer? _liveClockTimer;

  // Location & Weather & Nearby Explore State
  String? _currentCity;
  // ignore: unused_field
  String? _currentCountry;
  double? _userLatitude;
  double? _userLongitude;
  int? _temperatureCelsius;
  String? _weatherDescription;
  // ignore: unused_field
  String _weatherEmoji = '🌤️';
  // ignore: unused_field
  List<NearbyPlace> _nearbyPlaces = [];
  // ignore: unused_field
  bool _isLoadingPlaces = false;

  static const Map<String, List<double>> _cityCoordinates = {
    'bengaluru': [12.9716, 77.5946],
    'bangalore': [12.9716, 77.5946],
    'chennai': [13.0827, 80.2707],
    'mumbai': [19.0760, 72.8777],
    'delhi': [28.6139, 77.2090],
    'goa': [15.2993, 74.1240],
    'baga': [15.5524, 73.7517],
    'calangute': [15.5439, 73.7554],
    'panaji': [15.4909, 73.8278],
    'hyderabad': [17.3850, 78.4867],
    'kolkata': [22.5726, 88.3639],
    'pune': [18.5204, 73.8567],
    'jaipur': [26.9124, 75.7873],
    'kochi': [9.9312, 76.2673],
    'coimbatore': [11.0168, 76.9558],
    'pondy': [11.9416, 79.8083],
    'pondicherry': [11.9416, 79.8083],
    'manali': [32.2432, 77.1892],
    'rome': [41.9028, 12.4964],
    'paris': [48.8566, 2.3522],
    'tokyo': [35.6762, 139.6503],
    'bali': [-8.3405, 115.0920],
  };

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_trackScrollVelocity);
    _initLocationAndWeather();

    _liveClockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });

    _notificationWatcherSub = TripNotificationWatcher.instance.onNewEventStream.listen((event) {
      final activeTrip = ref.read(activeTripProvider);
      if (activeTrip != null && mounted) {
        _loadCrewNotifications(activeTrip.id);
      }
    });
  }

  void _loadTripDetails(String tripId, TripModel trip) {
    final isNewTrip = _lastLoadedTripId != tripId;
    _lastLoadedTripId = tripId;

    if (isNewTrip) {
      _setupItinerarySubscription(tripId);
    }
    _loadCrewNotifications(tripId);

    if (!SupabaseService.isInitialized) {
      _upcomingItinerary = [];
      _crewActivityText = null;
      return;
    }

    Future.microtask(() async {
      try {
        final itinRes = await SupabaseService.client
            .from('itinerary_items')
            .select()
            .eq('trip_id', tripId);

        List<ItineraryItem> items = [];
        if (itinRes.isNotEmpty) {
          items = itinRes
              .map(
                (doc) => ItineraryItem.fromMap(
                  Map<String, dynamic>.from(doc),
                  doc['id']?.toString() ?? '',
                ),
              )
              .toList();
          items.sort((a, b) {
            final dayCmp = a.dayNumber.compareTo(b.dayNumber);
            if (dayCmp != 0) return dayCmp;
            final orderCmp = a.order.compareTo(b.order);
            if (orderCmp != 0) return orderCmp;
            return a.time.compareTo(b.time);
          });
        }

        // Query real crew activity updates strictly from database
        String? latestActivity;

        // 1. Most recent expense by any crew member
        try {
          final expRes = await SupabaseService.client
              .from('expenses')
              .select('paid_by_name, description, amount_paise, category, created_at')
              .eq('trip_id', tripId)
              .order('created_at', ascending: false)
              .limit(1);

          if (expRes.isNotEmpty) {
            final exp = expRes.first;
            final payer = exp['paid_by_name'] as String? ?? 'A crew member';
            final desc = exp['description'] as String? ?? 'expense';
            final paise = exp['amount_paise'] as num? ?? 0;
            final amountStr = paise > 0 ? '₹${(paise / 100).toStringAsFixed(0)}' : '';
            final cat = (exp['category'] as String? ?? '').toLowerCase();
            String catEmoji = '💳';
            if (cat.contains('food') || cat.contains('dine') || cat.contains('meal')) {
              catEmoji = '🍕';
            } else if (cat.contains('travel') || cat.contains('train') || cat.contains('flight') || cat.contains('cab')) {
              catEmoji = '🚆';
            } else if (cat.contains('fuel') || cat.contains('gas')) {
              catEmoji = '⛽';
            } else if (cat.contains('stay') || cat.contains('hotel')) {
              catEmoji = '🏨';
            }

            final timeAgo = _formatTimeAgoString(exp['created_at']);
            latestActivity = amountStr.isNotEmpty
                ? '$payer paid $amountStr for $desc $catEmoji · $timeAgo'
                : '$payer paid for $desc $catEmoji · $timeAgo';
          }
        } catch (_) {}

        // 2. Most recent Trip Pot transaction
        if (latestActivity == null) {
          try {
            final txRes = await SupabaseService.client
                .from('transactions')
                .select('user_name, amount, type, created_at')
                .eq('trip_id', tripId)
                .order('created_at', ascending: false)
                .limit(1);
            if (txRes.isNotEmpty) {
              final tx = txRes.first;
              final user = tx['user_name'] as String? ?? 'A crew member';
              final amt = tx['amount'] as num? ?? 0;
              final type = tx['type'] as String? ?? 'contribution';
              final timeAgo = _formatTimeAgoString(tx['created_at']);
              if (type == 'expense' || type == 'spending') {
                latestActivity = '$user spent ₹$amt from Trip Pot 💸 · $timeAgo';
              } else {
                latestActivity = '$user added ₹$amt to Trip Pot 💰 · $timeAgo';
              }
            }
          } catch (_) {}
        }

        // 3. Most recent check-in / pulse
        if (latestActivity == null) {
          try {
            final pulseRes = await SupabaseService.client
                .from('trip_pulses')
                .select('user_name, pulse_type, type, created_at')
                .eq('trip_id', tripId)
                .order('created_at', ascending: false)
                .limit(1);
            if (pulseRes.isNotEmpty) {
              final pulse = pulseRes.first;
              final user = pulse['user_name'] as String? ?? 'A crew member';
              final status = pulse['pulse_type'] as String? ?? 'Checked in';
              final timeAgo = _formatTimeAgoString(pulse['created_at']);
              latestActivity = '$user is feeling: $status · $timeAgo';
            }
          } catch (_) {}
        }

        // 4. Most recent crew member joined
        if (latestActivity == null && trip.memberCount > 1) {
          try {
            final memRes = await SupabaseService.client
                .from('trip_members')
                .select('user_name, created_at')
                .eq('trip_id', tripId)
                .order('created_at', ascending: false)
                .limit(1);
            if (memRes.isNotEmpty) {
              final mem = memRes.first;
              final name = mem['user_name'] as String?;
              if (name != null && name.isNotEmpty) {
                final timeAgo = _formatTimeAgoString(mem['created_at']);
                latestActivity = '$name joined the crew 🎒 · $timeAgo';
              }
            }
          } catch (_) {}
        }

        // Resolve trip status overrides and crew members with real names
        List<String> resolvedNames = [];
        String resolvedMyName = '';
        try {
          final prefs = await SharedPreferences.getInstance();
          final savedStatus = prefs.getString('trip_status_$tripId');
          if (savedStatus != null && savedStatus.isNotEmpty && mounted) {
            _tripStatusOverrides[tripId] = savedStatus;
          }

          final saved = prefs.getStringList('trip_crew_names_$tripId');
          if (saved != null && saved.isNotEmpty) {
            resolvedNames = List<String>.from(saved);
            if (resolvedNames[0].trim().isNotEmpty &&
                resolvedNames[0] != 'Traveler' &&
                resolvedNames[0] != 'You') {
              resolvedMyName = resolvedNames[0].trim();
            }
          }

          if (resolvedMyName.isEmpty) {
            final custom = prefs.getString('user_custom_name');
            if (custom != null && custom.trim().isNotEmpty && custom != 'Traveler') {
              resolvedMyName = custom.trim();
            }
          }
        } catch (_) {}

        final authUser = ref.read(authProvider).user;
        if (resolvedMyName.isEmpty) {
          if (authUser?.name != null &&
              authUser!.name.trim().isNotEmpty &&
              authUser.name.trim() != 'Traveler') {
            resolvedMyName = authUser.name.trim();
          } else {
            resolvedMyName = 'Traveler';
          }
        }
        final myName = resolvedMyName;

        // Load blacklists of removed members
        final prefs = await SharedPreferences.getInstance();
        final removedUids = (prefs.getStringList('removed_crew_uids_$tripId') ?? []).toSet();
        final removedNames = (prefs.getStringList('removed_crew_names_$tripId') ?? []).toSet();

        // Resolve real names of members who joined the trip in Supabase
        final Map<String, String> uidToRealName = {};
        if (SupabaseService.isInitialized) {
          try {
            final memRes = await SupabaseService.client
                .from('trip_members')
                .select('user_id, role, joined_at')
                .eq('trip_id', tripId)
                .order('joined_at', ascending: true);

            final otherUids = memRes
                .map((r) => r['user_id']?.toString() ?? '')
                .where((uid) => uid.isNotEmpty && uid != authUser?.uid && !removedUids.contains(uid))
                .toSet()
                .toList();

            if (otherUids.isNotEmpty) {
              // 1. Try profiles table
              try {
                final profRes = await SupabaseService.client
                    .from('profiles')
                    .select('id, display_name')
                    .inFilter('id', otherUids);
                for (final p in profRes) {
                  final uid = p['id']?.toString() ?? '';
                  final dName = (p['display_name'] as String? ?? '').trim();
                  if (uid.isNotEmpty && dName.isNotEmpty && !removedNames.contains(dName)) {
                    uidToRealName[uid] = dName;
                  }
                }
              } catch (_) {}

              // 2. Try transactions table (initiated_by_name)
              final remainingUids1 = otherUids.where((u) => !uidToRealName.containsKey(u)).toList();
              if (remainingUids1.isNotEmpty) {
                try {
                  final txRes = await SupabaseService.client
                      .from('transactions')
                      .select('initiated_by_user_id, initiated_by_name')
                      .eq('trip_id', tripId)
                      .inFilter('initiated_by_user_id', remainingUids1);
                  for (final tx in txRes) {
                    final uid = tx['initiated_by_user_id']?.toString() ?? '';
                    final name = (tx['initiated_by_name'] as String? ?? '').trim();
                    if (uid.isNotEmpty && name.isNotEmpty && !uidToRealName.containsKey(uid) && !removedNames.contains(name)) {
                      uidToRealName[uid] = name;
                    }
                  }
                } catch (_) {}
              }

              // 3. Try expenses table (paid_by_name)
              final remainingUids2 = otherUids.where((u) => !uidToRealName.containsKey(u)).toList();
              if (remainingUids2.isNotEmpty) {
                try {
                  final expRes = await SupabaseService.client
                      .from('expenses')
                      .select('paid_by_user_id, paid_by_name')
                      .eq('trip_id', tripId)
                      .inFilter('paid_by_user_id', remainingUids2);
                  for (final exp in expRes) {
                    final uid = exp['paid_by_user_id']?.toString() ?? '';
                    final name = (exp['paid_by_name'] as String? ?? '').trim();
                    if (uid.isNotEmpty && name.isNotEmpty && name.toLowerCase() != 'member' && !uidToRealName.containsKey(uid) && !removedNames.contains(name)) {
                      uidToRealName[uid] = name;
                    }
                  }
                } catch (_) {}
              }
            }
          } catch (_) {}
        }

        final List<String> finalCrewNames = [];
        finalCrewNames.add(myName);

        // If user previously saved crew names, respect that exact list and don't resurrect removed members
        if (resolvedNames.length > 1) {
          for (int i = 1; i < resolvedNames.length; i++) {
            final n = resolvedNames[i].trim();
            if (n.isNotEmpty && !removedNames.contains(n)) {
              finalCrewNames.add(n);
            }
          }
        } else {
          // If no custom crew names were saved, populate from live otherRealNames
          final otherRealNames = uidToRealName.values.toList();
          for (final rName in otherRealNames) {
            if (rName.isNotEmpty &&
                rName != myName &&
                !removedNames.contains(rName) &&
                !finalCrewNames.contains(rName)) {
              finalCrewNames.add(rName);
            }
          }
        }

        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setStringList('trip_crew_names_$tripId', finalCrewNames);
        } catch (_) {}

        resolvedNames = finalCrewNames;

        if (mounted) {
          setState(() {
            _upcomingItinerary = items;
            _crewActivityText = latestActivity;
            _tripCrewNames = resolvedNames;
            _cachedUserName = myName;
          });
        }
      } catch (_) {
        // Fallback safely
      }
    });
  }

  void _setupItinerarySubscription(String tripId) {
    _itinerarySub?.cancel();
    if (!SupabaseService.isInitialized) return;

    try {
      _itinerarySub = SupabaseService.client
          .from('itinerary_items')
          .stream(primaryKey: ['id'])
          .eq('trip_id', tripId)
          .listen((data) {
        final items = data
            .map((doc) => ItineraryItem.fromMap(
                  Map<String, dynamic>.from(doc),
                  doc['id']?.toString() ?? '',
                ))
            .toList();
        items.sort((a, b) {
          final dayCmp = a.dayNumber.compareTo(b.dayNumber);
          if (dayCmp != 0) return dayCmp;
          final orderCmp = a.order.compareTo(b.order);
          if (orderCmp != 0) return orderCmp;
          return a.time.compareTo(b.time);
        });

        if (mounted) {
          setState(() {
            _upcomingItinerary = items;
          });
        }
      }, onError: (_) {});
    } catch (_) {}
  }

  Future<void> _loadCrewNotifications(String tripId) async {
    if (!SupabaseService.isInitialized) return;
    try {
      final List<_CrewNotification> notifs = [];

      // 1. Itinerary stops added/updated
      try {
        final itin = await SupabaseService.client
            .from('itinerary_items')
            .select('id, title, time, day_number, created_at')
            .eq('trip_id', tripId)
            .order('created_at', ascending: false)
            .limit(3);
        for (final item in itin) {
          final title = item['title'] as String? ?? 'New stop';
          final day = item['day_number'] ?? 1;
          final time = item['time'] ?? '';
          notifs.add(_CrewNotification(
            id: 'itin_${item['id']}',
            title: 'Itinerary Stop Added',
            subtitle: '$title · Day $day ($time)',
            timeAgo: _formatTimeAgoString(item['created_at']),
            icon: Icons.place_rounded,
            iconColor: const Color(0xFFEF4444),
            route: '/itinerary',
          ));
        }
      } catch (_) {}

      // 2. Expenses logged
      try {
        final exp = await SupabaseService.client
            .from('expenses')
            .select('id, paid_by_name, description, amount_paise, created_at')
            .eq('trip_id', tripId)
            .order('created_at', ascending: false)
            .limit(3);
        for (final item in exp) {
          final payer = item['paid_by_name'] as String? ?? 'Crew member';
          final desc = item['description'] as String? ?? 'expense';
          final paise = item['amount_paise'] as num? ?? 0;
          final amt = paise > 0 ? '₹${(paise / 100).toStringAsFixed(0)}' : '';
          notifs.add(_CrewNotification(
            id: 'exp_${item['id']}',
            title: 'Expense Logged',
            subtitle: amt.isNotEmpty ? '$payer paid $amt for $desc' : '$payer logged $desc',
            timeAgo: _formatTimeAgoString(item['created_at']),
            icon: Icons.account_balance_wallet_rounded,
            iconColor: const Color(0xFFF59E0B),
            route: '/expenses',
          ));
        }
      } catch (_) {}

      // 3. Memories uploaded
      try {
        final mem = await SupabaseService.client
            .from('memories')
            .select('id, caption, user_name, created_at')
            .eq('trip_id', tripId)
            .order('created_at', ascending: false)
            .limit(3);
        for (final item in mem) {
          final uName = item['user_name'] as String? ?? 'Crew member';
          final cap = item['caption'] as String? ?? 'Shared a photo';
          notifs.add(_CrewNotification(
            id: 'mem_${item['id']}',
            title: 'New Memory Photo',
            subtitle: '$uName: $cap',
            timeAgo: _formatTimeAgoString(item['created_at']),
            icon: Icons.photo_library_rounded,
            iconColor: const Color(0xFF8B5CF6),
            route: '/memories',
          ));
        }
      } catch (_) {}

      // 4. Pulses / Check-ins
      try {
        final pulse = await SupabaseService.client
            .from('trip_pulses')
            .select('id, user_name, pulse_type, created_at')
            .eq('trip_id', tripId)
            .order('created_at', ascending: false)
            .limit(3);
        for (final item in pulse) {
          final uName = item['user_name'] as String? ?? 'Crew member';
          final status = item['pulse_type'] as String? ?? 'Checked in';
          notifs.add(_CrewNotification(
            id: 'pulse_${item['id']}',
            title: 'Live Crew Pulse',
            subtitle: '$uName: $status',
            timeAgo: _formatTimeAgoString(item['created_at']),
            icon: Icons.favorite_rounded,
            iconColor: const Color(0xFFEC4899),
            route: '/pulse',
          ));
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _crewNotifications = notifs;
        });
      }
    } catch (_) {}
  }

  void _showTripNotificationsSheet(BuildContext context, TripModel? activeTrip) {
    if (activeTrip == null) return;

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CrewUpdatesSheet(
        tripId: activeTrip.id,
        initialNotifications: _crewNotifications,
        onNotificationsUpdated: (updatedList) {
          if (mounted) {
            setState(() {
              _crewNotifications = updatedList;
            });
          }
        },
      ),
    );
  }

  String _formatTimeAgoString(dynamic createdAtRaw) {
    if (createdAtRaw == null) return 'just now';
    DateTime? dt;
    if (createdAtRaw is DateTime) {
      dt = createdAtRaw.toLocal();
    } else {
      final str = createdAtRaw.toString();
      final parsed = DateTime.tryParse(str);
      if (parsed != null) {
        final local = parsed.toLocal();
        // Guard against double timezone shift (if local is >2 min in the future)
        if (local.isAfter(DateTime.now().add(const Duration(minutes: 2)))) {
          dt = parsed;
        } else {
          dt = local;
        }
      }
    }
    if (dt == null) return 'recently';
    // Clamp future timestamps to current time
    if (dt.isAfter(DateTime.now())) {
      dt = DateTime.now();
    }
    final diff = DateTime.now().difference(dt);
    final timeStr = DateFormat('hh:mm a').format(dt);
    if (diff.inMinutes < 1) return '$timeStr · just now';
    if (diff.inMinutes < 60) return '$timeStr · ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '$timeStr · ${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago, $timeStr';
    return DateFormat('d MMM, hh:mm a').format(dt);
  }

  void _trackScrollVelocity() {
    final now = DateTime.now();
    final pixels = _scrollController.position.pixels;
    final previousAt = _lastScrollAt;
    if (previousAt != null) {
      final elapsedMs = now.difference(previousAt).inMilliseconds;
      if (elapsedMs > 0) {
        _scrollVelocity.value = ((pixels - _lastScrollPixels) / elapsedMs / 1.2)
            .clamp(-1.0, 1.0)
            .toDouble();
      }
    }
    _lastScrollAt = now;
    _lastScrollPixels = pixels;
    _velocityDecay?.cancel();
    _velocityDecay = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      final next = _scrollVelocity.value * .78;
      if (next.abs() < .015) {
        _scrollVelocity.value = 0;
        _lastScrollAt = null;
        timer.cancel();
      } else {
        _scrollVelocity.value = next;
      }
    });
  }

  @override
  void dispose() {
    _liveClockTimer?.cancel();
    _notificationWatcherSub?.cancel();
    _itinerarySub?.cancel();
    _velocityDecay?.cancel();
    _scrollController
      ..removeListener(_trackScrollVelocity)
      ..dispose();
    _scrollVelocity.dispose();
    super.dispose();
  }

  Future<void> _initLocationAndWeather() async {
    final now = DateTime.now();
    _setHourlyWeatherFallback(now.hour);

    final isTest = Platform.environment.containsKey('FLUTTER_TEST');
    if (isTest) {
      _currentCity = 'Rome';
      _currentCountry = 'Italy';
      _nearbyPlaces = PlacesService.generateContextualFallback(12.9716, 77.5946, 'Rome', null);
      return;
    }

    // 1. Immediately check fast/cached location (<15ms)
    final fastLoc = await LocationService.getFastLocation();
    if (fastLoc != null && mounted) {
      setState(() {
        _currentCity = fastLoc.city;
        _currentCountry = fastLoc.country;
        _userLatitude = fastLoc.latitude;
        _userLongitude = fastLoc.longitude;
      });
      _fetchWeather(fastLoc.latitude, fastLoc.longitude);
      _loadNearbyPlaces(fastLoc.latitude, fastLoc.longitude);
    } else {
      if (mounted) {
        setState(() {
          _isLoadingPlaces = true;
          _nearbyPlaces = [];
        });
      }
    }

    // 2. Fetch fresh, accurate position
    final freshLoc = await LocationService.getFreshLocation();
    if (freshLoc != null) {
      if (mounted) {
        setState(() {
          _currentCity = freshLoc.city;
          _currentCountry = freshLoc.country;
          _userLatitude = freshLoc.latitude;
          _userLongitude = freshLoc.longitude;
        });
      }
      await _fetchWeather(freshLoc.latitude, freshLoc.longitude);
      await _loadNearbyPlaces(freshLoc.latitude, freshLoc.longitude);
    } else if (_currentCity == null) {
      // If location is completely denied or unavailable, use active trip or neutral local
      final activeTrip = ref.read(tripsProvider).activeTrip;
      if (activeTrip != null && activeTrip.destination.isNotEmpty) {
        final coords = _getCityCoordinates(activeTrip.destination);
        if (mounted) {
          setState(() {
            _currentCity = activeTrip.destination;
          });
        }
        await _fetchWeather(coords[0], coords[1]);
        await _loadNearbyPlaces(coords[0], coords[1]);
      } else {
        final coords = _getCityCoordinates('Chennai');
        if (mounted) {
          setState(() {
            _currentCity = 'Local Area';
            _currentCountry = 'India';
          });
        }
        await _fetchWeather(coords[0], coords[1]);
        await _loadNearbyPlaces(coords[0], coords[1]);
      }
    }
  }

  List<double> _getCityCoordinates(String dest) {
    final clean = dest.toLowerCase().trim();
    for (final entry in _cityCoordinates.entries) {
      if (clean.contains(entry.key)) {
        return entry.value;
      }
    }
    return [12.9716, 77.5946];
  }



  Future<void> _fetchWeather(double lat, double lon) async {
    try {
      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,weather_code',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final current = json['current'] as Map<String, dynamic>?;
        if (current != null) {
          final temp = (current['temperature_2m'] as num?)?.round();
          final code = (current['weather_code'] as num?)?.toInt() ?? 1;

          String desc = 'sunny';
          String emoji = '☀️';
          if (code == 0) {
            desc = 'clear skies';
            emoji = '☀️';
          } else if (code <= 3) {
            desc = 'partly cloudy';
            emoji = '🌤️';
          } else if (code <= 48) {
            desc = 'misty / foggy';
            emoji = '🌫️';
          } else if (code <= 67) {
            desc = 'light rain';
            emoji = '🌧️';
          } else if (code <= 82) {
            desc = 'passing showers';
            emoji = '🌦️';
          } else {
            desc = 'thunderstorm';
            emoji = '⛈️';
          }

          if (mounted) {
            setState(() {
              if (temp != null) _temperatureCelsius = temp;
              _weatherDescription = desc;
              _weatherEmoji = emoji;
            });
          }
          return;
        }
      }
    } catch (e) {
      developer.log('Weather fetch error: $e', name: 'HomeScreen');
    }

    if (mounted) {
      setState(() {
        _setHourlyWeatherFallback(DateTime.now().hour);
      });
    }
  }

  void _setHourlyWeatherFallback(int hour) {
    if (hour >= 5 && hour < 11) {
      _temperatureCelsius ??= 24;
      _weatherDescription ??= 'fresh morning';
      _weatherEmoji = '🌤️';
    } else if (hour >= 11 && hour < 16) {
      _temperatureCelsius ??= 29;
      _weatherDescription ??= 'sunny';
      _weatherEmoji = '☀️';
    } else if (hour >= 16 && hour < 19) {
      _temperatureCelsius ??= 26;
      _weatherDescription ??= 'breezy afternoon';
      _weatherEmoji = '⛅';
    } else if (hour >= 19 && hour < 23) {
      _temperatureCelsius ??= 23;
      _weatherDescription ??= 'clear evening';
      _weatherEmoji = '🌆';
    } else {
      _temperatureCelsius ??= 21;
      _weatherDescription ??= 'peaceful night';
      _weatherEmoji = '🌙';
    }
  }

  Future<void> _loadNearbyPlaces(double lat, double lon) async {
    _userLatitude = lat;
    _userLongitude = lon;
    if (mounted) setState(() => _isLoadingPlaces = true);
    try {
      final places = await PlacesService.fetchNearbyPlaces(
        latitude: lat,
        longitude: lon,
        radiusMeters: 8000,
        cityContext: _currentCity,
      );
      if (mounted) {
        setState(() {
          _nearbyPlaces = places.take(10).toList();
          _isLoadingPlaces = false;
        });
      }
    } catch (e) {
      developer.log('Places load error: $e', name: 'HomeScreen');
      if (mounted) {
        setState(() {
          _isLoadingPlaces = false;
        });
      }
    }
  }

  // ignore: unused_element
  Future<void> _openDirectionsToPlace(NearbyPlace place) async {
    final double? uLat = _userLatitude;
    final double? uLon = _userLongitude;

    // Check if user is already at the destination location (< 50m)
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

    // 1. Android Native Google Maps Navigation intent (starts turn-by-turn navigation directly to place coordinates)
    final navUri = Uri.parse(
      'google.navigation:q=${place.latitude},${place.longitude}&mode=d',
    );

    // 2. Google Maps Universal directions URL (without forced origin so Google Maps uses phone's live GPS)
    final webMapsUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${place.latitude},${place.longitude}&travelmode=driving',
    );

    // 3. Fallback geo: URI with place coordinates and title
    final geoUri = Uri.parse(
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
        if (await canLaunchUrl(webMapsUri)) {
          await launchUrl(webMapsUri, mode: LaunchMode.externalApplication);
          return;
        }
      } catch (_) {}

      try {
        if (await canLaunchUrl(geoUri)) {
          await launchUrl(geoUri, mode: LaunchMode.externalApplication);
          return;
        }
      } catch (_) {}

      await launchUrl(webMapsUri, mode: LaunchMode.platformDefault);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open map app: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final authUser = ref.watch(authProvider).user;
    final tripsState = ref.watch(tripsProvider);
    final activeTrip = tripsState.activeTrip;

    if (activeTrip != null && activeTrip.id != _lastLoadedTripId) {
      _loadTripDetails(activeTrip.id, activeTrip);
    }

    return Scaffold(
      backgroundColor: isDark ? AppTheme.scaffoldDark : AppTheme.scaffoldLight,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          color: const Color(0xFF258CF4),
          child: SingleChildScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Header: Location, Live Time, Greetings & Notif, Profile
                _buildTopHeader(context, authUser, activeTrip),
                const SizedBox(height: 16),

                // Upcoming / Active Trip Card
                _buildActiveTripSection(context, activeTrip, authUser),
                const SizedBox(height: 16),

                // Trip Actions: Assistant, Chatroom, Invite
                _buildTripActionsRow(context, activeTrip),
                const SizedBox(height: 18),

                // Feature Grid (11 Items across 3 rows)
                _buildFeaturesGrid(context, isDark),

                // Safe clearance for bottom navigation capsule
                const SizedBox(height: 110),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onRefresh() async {
    _initLocationAndWeather();
    final authUser = ref.read(authProvider).user;
    if (authUser != null) {
      ref.read(tripsProvider.notifier).fetchUserTrips(authUser.uid);
    }
    final activeTrip = ref.read(tripsProvider).activeTrip;
    if (activeTrip != null) {
      _loadTripDetails(activeTrip.id, activeTrip);
      _loadCrewNotifications(activeTrip.id);
    }
    if (mounted) setState(() {});
  }

  Widget _buildTopHeader(
    BuildContext context,
    dynamic authUser,
    TripModel? activeTrip,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final locationDisplay = _currentCity != null && _currentCity!.isNotEmpty
        ? _currentCity!
        : (activeTrip?.destination.isNotEmpty == true
            ? activeTrip!.destination
            : 'Avadi');

    final now = DateTime.now();
    final timeStr = DateFormat('hh:mm a').format(now);

    final hour = now.hour;
    final String greetingTime = hour < 12
        ? 'Good morning'
        : (hour < 17 ? 'Good afternoon' : 'Good evening');

    final resolvedName = (_cachedUserName != null &&
            _cachedUserName!.isNotEmpty &&
            _cachedUserName != 'Traveler' &&
            _cachedUserName != 'You')
        ? _cachedUserName!
        : ((authUser?.name != null &&
                authUser!.name.toString().trim().isNotEmpty &&
                authUser.name.toString().trim() != 'Traveler')
            ? authUser.name.toString().trim()
            : 'Traveler');

    final firstName = resolvedName.split(' ').first;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Left Column: Location, Time, Greetings
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Location (current)
              InkWell(
                onTap: () => _showTripPickerSheet(context),
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.location_on_rounded,
                      size: 16,
                      color: AppTheme.terracotta,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        locationDisplay,
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : AppTheme.espresso,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: isDark ? Colors.white54 : AppTheme.mocha,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 3),

              // Time
              Text(
                timeStr,
                style: GoogleFonts.inter(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: isDark ? AppTheme.creamTextDark : AppTheme.espresso,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 2),

              // Greetings !!!
              Text(
                '$greetingTime, $firstName !!!',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppTheme.creamTextDark : AppTheme.espresso,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),

        // Right Row: Notif Bell & Profile Avatar
        Row(
          children: [
            // Notification Bell with Badge
            GestureDetector(
              onTap: () => _showTripNotificationsSheet(context, activeTrip),
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.espressoSurfaceDark : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark ? AppTheme.sandBorderDark : AppTheme.sand,
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      _crewNotifications.isNotEmpty
                          ? Icons.notifications_active_rounded
                          : Icons.notifications_outlined,
                      color: isDark ? Colors.white : AppTheme.espresso,
                      size: 22,
                    ),
                    if (_crewNotifications.isNotEmpty)
                      Positioned(
                        top: 5,
                        right: 5,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          decoration: const BoxDecoration(
                            color: AppTheme.sunset,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${_crewNotifications.length}',
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),

            // Profile Avatar
            InkWell(
              onTap: () => context.push('/profile'),
              borderRadius: BorderRadius.circular(21),
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark
                      ? AppTheme.espressoCardDark
                      : AppTheme.warmBeige,
                  border: Border.all(
                    color: isDark ? AppTheme.sandBorderDark : AppTheme.sand,
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: Text(
                    (firstName.isNotEmpty ? firstName[0] : 'U').toUpperCase(),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.espresso,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActiveTripSection(
    BuildContext context,
    TripModel? activeTrip,
    dynamic authUser,
  ) {
    // Even though the trip is over/completed/cancelled, do NOT display as active trip
    if (activeTrip == null || activeTrip.isPast || activeTrip.isCompleted || activeTrip.isCancelled) {
      return _buildNoActiveTripCard(context);
    }
    return _buildActiveTripCardContent(context, activeTrip, authUser);
  }

  Widget _buildNoActiveTripCard(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.espressoSurfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark ? AppTheme.sandBorderDark : AppTheme.sand,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'No Active Trip',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.caramel,
                ),
              ),
              InkWell(
                onTap: () => context.push('/trips'),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    children: [
                      Text(
                        'Trips',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.caramel,
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: AppTheme.caramel,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.caramel.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.flight_takeoff_rounded,
                  color: AppTheme.caramel,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ready For Your Next Journey?',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : AppTheme.espresso,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Plan a new adventure or view your past completed trips.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: isDark ? AppTheme.mochaTextDark : AppTheme.mocha,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => context.push('/create-trip'),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(
                'Create New Trip',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.espresso,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveTripCardContent(
    BuildContext context,
    TripModel activeTrip,
    dynamic authUser,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final overrideStatus = _tripStatusOverrides[activeTrip.id];
    final effectiveStatus = overrideStatus ?? activeTrip.status;
    final isCancelled = effectiveStatus == 'cancelled' ||
        effectiveStatus == 'not_carried_out' ||
        activeTrip.isCancelled;
    final isCompleted = effectiveStatus == 'completed' ||
        effectiveStatus == 'carried_out' ||
        activeTrip.isCompleted;
    final isPast = activeTrip.isPast;
    final isOngoing = !isCancelled && !isCompleted && activeTrip.isOngoing;
    final daysToGo = activeTrip.daysToGo;

    Color statusColor;
    String statusTitle;
    String timeStatusText;

    if (isCancelled) {
      statusColor = const Color(0xFFEF4444);
      statusTitle = 'Not Carried Out';
      timeStatusText = 'Cancelled / Not carried out';
    } else if (isCompleted) {
      statusColor = const Color(0xFF10B981);
      statusTitle = 'Carried Out ✓';
      timeStatusText = 'Trip completed';
    } else if (isPast) {
      statusColor = const Color(0xFFF59E0B);
      statusTitle = 'Past Trip';
      final endDay = DateTime(
        activeTrip.endDate.year,
        activeTrip.endDate.month,
        activeTrip.endDate.day,
      );
      final today = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
      );
      final daysDiff = today.difference(endDay).inDays;
      timeStatusText = daysDiff == 1
          ? 'Ended yesterday'
          : (daysDiff == 0 ? 'Ended today' : 'Ended $daysDiff days ago');
    } else if (isOngoing) {
      statusColor = const Color(0xFF10B981);
      statusTitle = 'Active Now';
      timeStatusText = 'Active Today';
    } else {
      statusColor = const Color(0xFF38BDF8);
      statusTitle = 'Upcoming';
      timeStatusText = daysToGo == 1
          ? 'Starts tomorrow'
          : (daysToGo == 0 ? 'Starts today' : 'Starts in $daysToGo days');
    }

    final resolvedMyName = (_cachedUserName != null &&
            _cachedUserName!.isNotEmpty &&
            _cachedUserName != 'Traveler' &&
            _cachedUserName != 'You')
        ? _cachedUserName!
        : ((_tripCrewNames.isNotEmpty &&
                _tripCrewNames[0].isNotEmpty &&
                _tripCrewNames[0] != 'Traveler' &&
                _tripCrewNames[0] != 'You')
            ? _tripCrewNames[0]
            : ((authUser?.name != null &&
                    authUser!.name.toString().trim().isNotEmpty &&
                    authUser.name.toString().trim() != 'Traveler')
                ? authUser.name.toString().trim()
                : 'Traveler'));

    final List<String> crewNames = _tripCrewNames.isNotEmpty
        ? <String>[resolvedMyName, ..._tripCrewNames.skip(1)]
        : <String>[
            resolvedMyName,
            if (activeTrip.memberCount > 1)
              ...List.generate(
                activeTrip.memberCount - 1,
                (i) => 'Member ${i + 2}',
              ),
          ];

    final crewSummary = crewNames.length == 1
        ? '${crewNames.first} (You)'
        : (crewNames.length == 2
            ? '${crewNames[0]} & ${crewNames[1]}'
            : '${crewNames[0]} + ${crewNames.length - 1} crew');

    final routeDisplay = activeTrip.startingPlace.isNotEmpty &&
            activeTrip.startingPlace != activeTrip.destination
        ? '${activeTrip.startingPlace} → ${activeTrip.destination}'
        : activeTrip.destination;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.espressoSurfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? AppTheme.sandBorderDark : AppTheme.sand,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.05),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Active / Upcoming Trip (Left) & Trips (Right)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isOngoing ? AppTheme.sage : AppTheme.caramel,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isOngoing ? 'Active Trip' : 'Upcoming Trip',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: isOngoing ? AppTheme.sage : AppTheme.caramel,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () => context.push('/trips'),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Trips',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.caramel,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: AppTheme.caramel,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Destination Route Title
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activeTrip.destination,
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white : AppTheme.espresso,
                        letterSpacing: -0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (routeDisplay != activeTrip.destination) ...[
                      const SizedBox(height: 2),
                      Text(
                        routeDisplay,
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppTheme.mochaTextDark : AppTheme.mocha,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              InkWell(
                onTap: () => _showChangeStatusDialog(context, activeTrip),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    statusTitle,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: statusColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Dates & Status subline
          Text(
            '${DateFormat('d MMM').format(activeTrip.startDate)} - ${DateFormat('d MMM').format(activeTrip.endDate)} · $timeStatusText',
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: isDark ? AppTheme.mochaTextDark : AppTheme.mocha,
            ),
          ),
          const SizedBox(height: 14),

          // Members / Crew row (tap to edit names)
          InkWell(
            onTap: () => _showCrewNamesSheet(context, activeTrip),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : AppTheme.warmBeige.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? AppTheme.sandBorderDark : AppTheme.sand,
                ),
              ),
              child: Row(
                children: [
                  _buildHeaderCrewAvatarsList(crewNames),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Members / crew',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: isDark ? AppTheme.mochaTextDark : AppTheme.mocha,
                            letterSpacing: 0.3,
                          ),
                        ),
                        Text(
                          crewSummary,
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : AppTheme.espresso,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.edit_outlined,
                    size: 14,
                    color: AppTheme.caramel,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Direct to reviews & live maps
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showPlaceReviewsModal(context, activeTrip),
                  icon: const Icon(Icons.rate_review_rounded, size: 16, color: AppTheme.caramel),
                  label: Text(
                    'Reviews',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : AppTheme.espresso,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: isDark ? AppTheme.sandBorderDark : AppTheme.sand,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/map'),
                  icon: const Icon(
                    Icons.navigation_rounded,
                    size: 16,
                    color: AppTheme.caramel,
                  ),
                  label: Text(
                    'Live Maps',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : AppTheme.espresso,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: isDark ? AppTheme.sandBorderDark : AppTheme.sand,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // INSIGHT Button
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => context.push('/workspace'),
              icon: const Icon(Icons.insights_rounded, size: 18),
              label: Text(
                'INSIGHT',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.espresso,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPlaceReviewsModal(BuildContext context, TripModel trip) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.espressoSurface : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.4),
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
                      color: const Color(0xFF258CF4).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.photo_library_rounded,
                      color: Color(0xFF258CF4),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trip.destination,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Row(
                          children: [
                            Icon(Icons.star_rounded, size: 15, color: Color(0xFFFFB800)),
                            SizedBox(width: 4),
                            Text(
                              '4.8 (1,420+ Traveler Reviews)',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Top Crew Experiences & Highlights',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.black.withValues(alpha: 0.06),
                  ),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🌅 Golden Hour & Scenic Promenade',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Arrive early morning or around 5:30 PM for gentle sea breezes, street food carnivals, and the iconic lighthouse vantage point.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.black.withValues(alpha: 0.06),
                  ),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '📸 Top Photography Spots',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Great wide shots near the beach entrance and lighthouse observatory deck. Tripod photography allowed during non-peak morning hours.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final query = Uri.encodeComponent('${trip.destination} reviews');
                        final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
                        try {
                          await launchUrl(url, mode: LaunchMode.externalApplication);
                        } catch (_) {}
                      },
                      icon: const Icon(Icons.star_rounded, size: 16, color: Color(0xFFFFB800)),
                      label: const Text('Google Reviews'),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppTheme.copper),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        AiAssistantDialog.show(context);
                      },
                      icon: const Icon(Icons.auto_awesome, size: 16),
                      label: const Text('Ask AI Insights'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.copper,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTripActionsRow(
    BuildContext context,
    TripModel? activeTrip,
  ) {
    return Row(
      children: [
        Expanded(
          child: _buildTripActionButton(
            context,
            icon: Icons.auto_awesome_rounded,
            iconColor: AppTheme.caramel,
            title: 'Assistant',
            onTap: () {
              if (activeTrip != null) {
                AiAssistantDialog.show(context);
              } else {
                context.push('/ai');
              }
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildTripActionButton(
            context,
            icon: Icons.forum_rounded,
            iconColor: AppTheme.terracotta,
            title: 'Chatroom',
            onTap: () {
              context.push('/chat');
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildTripActionButton(
            context,
            icon: Icons.person_add_alt_1_rounded,
            iconColor: AppTheme.sage,
            title: 'Invite',
            onTap: () {
              if (activeTrip != null) {
                TripShareService.showQrModal(
                  context,
                  inviteCode: activeTrip.inviteCode,
                  tripName: activeTrip.name,
                  tripId: activeTrip.id,
                  startingPlace: activeTrip.startingPlace,
                  destination: activeTrip.destination,
                  startDate: activeTrip.startDate,
                  endDate: activeTrip.endDate,
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please select or create an active trip first'),
                  ),
                );
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTripActionButton(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.espressoSurfaceDark : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? AppTheme.sandBorderDark : AppTheme.sand,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 21),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : AppTheme.espresso,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeaturesGrid(BuildContext context, bool isDark) {
    return Column(
      children: [
        // Row 1: PAY, ITINERARY, EXP & SETTLE, CHECKLIST
        Row(
          children: [
            Expanded(
              child: _buildGridFeatureCard(
                context,
                title: 'PAY',
                icon: Icons.payments_rounded,
                color: AppTheme.sage,
                route: '/trip-pay',
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildGridFeatureCard(
                context,
                title: 'ITINERARY',
                icon: Icons.calendar_today_rounded,
                color: AppTheme.terracotta,
                route: '/itinerary',
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildGridFeatureCard(
                context,
                title: 'EXP & SETTLE',
                icon: Icons.receipt_long_rounded,
                color: AppTheme.caramel,
                route: '/expenses',
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildGridFeatureCard(
                context,
                title: 'CHECKLIST',
                icon: Icons.checklist_rounded,
                color: AppTheme.mutedBlue,
                route: '/checklist',
                isDark: isDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Row 2: TRIP PULSE, BUDGET EXP, LIVE CREW, MAPS & ROUTE
        Row(
          children: [
            Expanded(
              child: _buildGridFeatureCard(
                context,
                title: 'TRIP PULSE',
                icon: Icons.monitor_heart_rounded,
                color: AppTheme.terracotta,
                route: '/pulse',
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildGridFeatureCard(
                context,
                title: 'BUDGET EXP',
                icon: Icons.travel_explore_rounded,
                color: AppTheme.caramel,
                route: '/budget-explorer',
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildGridFeatureCard(
                context,
                title: 'LIVE CREW',
                icon: Icons.radar_rounded,
                color: AppTheme.sage,
                route: '/live-location',
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildGridFeatureCard(
                context,
                title: 'MAPS & ROUTE',
                icon: Icons.map_rounded,
                color: AppTheme.mutedBlue,
                route: '/map',
                isDark: isDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Row 3: MEMORIES, RECAP, SOS (with special red outline)
        Row(
          children: [
            Expanded(
              child: _buildGridFeatureCard(
                context,
                title: 'MEMORIES',
                icon: Icons.photo_library_rounded,
                color: AppTheme.sunset,
                route: '/memories',
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildGridFeatureCard(
                context,
                title: 'RECAP',
                icon: Icons.auto_awesome_motion_rounded,
                color: AppTheme.mocha,
                route: '/recap',
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildGridFeatureCard(
                context,
                title: 'SOS',
                icon: Icons.emergency_rounded,
                color: const Color(0xFFDC2626),
                route: '/safety',
                isDark: isDark,
                isEmergency: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGridFeatureCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required String route,
    required bool isDark,
    bool isEmergency = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push(route),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.espressoSurfaceDark : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isEmergency
                  ? const Color(0xFFDC2626)
                  : (isDark
                      ? AppTheme.sandBorderDark
                      : AppTheme.sand),
              width: isEmergency ? 1.8 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: isEmergency
                    ? const Color(0xFFDC2626).withValues(alpha: 0.25)
                    : Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                blurRadius: isEmergency ? 10 : 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 19),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: isEmergency
                      ? const Color(0xFFDC2626)
                      : (isDark ? Colors.white : AppTheme.espresso),
                  letterSpacing: -0.2,
                  decoration: isEmergency ? TextDecoration.underline : null,
                  decorationColor: const Color(0xFFDC2626),
                  decorationThickness: 2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCrewAvatarsList(List<String> names) {
    final displayNames = names.take(3).toList();
    const avatarSize = 24.0;
    final colors = [
      const Color(0xFF3B82F6),
      const Color(0xFF10B981),
      const Color(0xFFF59E0B),
      const Color(0xFF8B5CF6),
    ];

    return SizedBox(
      width: (avatarSize * 0.72 * (displayNames.length - 1)) + avatarSize,
      height: avatarSize,
      child: Stack(
        children: List.generate(displayNames.length, (index) {
          final name = displayNames[index].trim();
          final initial = name.isNotEmpty ? name[0].toUpperCase() : 'M';
          final color = colors[index % colors.length];

          return Positioned(
            left: index * (avatarSize * 0.72),
            child: Container(
              width: avatarSize,
              height: avatarSize,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.8),
                boxShadow: const [
                  BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 1)),
                ],
              ),
              child: Center(
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  void _showCrewNamesSheet(BuildContext context, TripModel trip) async {
    final authUser = ref.read(authProvider).user;
    final myDefaultName = (authUser?.name.toString().trim().isNotEmpty == true ? authUser!.name.toString().trim() : 'You');

    // Query real trip_members and their names so we can map each companion to their actual UID
    final Map<String, String> nameToUid = {};
    final List<Map<String, dynamic>> realMemberRows = [];
    if (SupabaseService.isInitialized) {
      try {
        final memRes = await SupabaseService.client
            .from('trip_members')
            .select('user_id, role, joined_at')
            .eq('trip_id', trip.id)
            .order('joined_at', ascending: true);
        realMemberRows.addAll(List<Map<String, dynamic>>.from(memRes));
        final otherUids = realMemberRows
            .map((r) => r['user_id']?.toString() ?? '')
            .where((uid) => uid.isNotEmpty && uid != authUser?.uid)
            .toList();
        if (otherUids.isNotEmpty) {
          final profRes = await SupabaseService.client
              .from('profiles')
              .select('id, display_name')
              .inFilter('id', otherUids);
          for (final p in profRes) {
            final uid = p['id']?.toString() ?? '';
            final name = (p['display_name'] as String? ?? '').trim();
            if (uid.isNotEmpty && name.isNotEmpty) {
              nameToUid[name] = uid;
            }
          }
        }
      } catch (_) {}
    }

    final List<_CompanionEntry> entries = [];
    if (_tripCrewNames.isNotEmpty) {
      for (int i = 0; i < _tripCrewNames.length; i++) {
        final name = _tripCrewNames[i];
        final isMe = i == 0;
        String? uid = isMe ? authUser?.uid : nameToUid[name];
        if (!isMe && uid == null && (i - 1) < realMemberRows.length) {
          final candidateUid = realMemberRows[i - 1]['user_id']?.toString();
          if (candidateUid != authUser?.uid) {
            uid = candidateUid;
          }
        }
        entries.add(_CompanionEntry(
          controller: TextEditingController(text: name),
          userId: uid,
          isOrganizer: isMe,
        ));
      }
    } else {
      entries.add(_CompanionEntry(
        controller: TextEditingController(text: myDefaultName),
        userId: authUser?.uid,
        isOrganizer: true,
      ));
      final target = math.max(trip.memberCount, 2);
      for (int i = 1; i < target; i++) {
        final otherIdx = i - 1;
        String? uid;
        if (otherIdx < realMemberRows.length) {
          final candidateUid = realMemberRows[otherIdx]['user_id']?.toString();
          if (candidateUid != authUser?.uid) uid = candidateUid;
        }
        entries.add(_CompanionEntry(
          controller: TextEditingController(text: 'Member ${i + 1}'),
          userId: uid,
          isOrganizer: false,
        ));
      }
    }

    final List<String> removedUserIds = [];
    final List<String> removedNames = [];

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final theme = Theme.of(sheetContext);
            final isDark = theme.brightness == Brightness.dark;
            final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;
            final bottomPadding = MediaQuery.of(sheetContext).padding.bottom;

            return SafeArea(
              top: false,
              child: Container(
                margin: EdgeInsets.only(bottom: bottomInset),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F1B2B) : Colors.white,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: const [
                    BoxShadow(color: Colors.black38, blurRadius: 20, offset: Offset(0, -4)),
                  ],
                ),
                padding: EdgeInsets.fromLTRB(20, 16, 20, math.max(28, bottomPadding + 20)),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFE600),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.people_alt_rounded, color: Colors.black, size: 20),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Who is Traveling in Your Crew?',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Give names to your travel companions so everyone is called by their real name.',
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      ...List.generate(entries.length, (index) {
                        final isMe = index == 0;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: index == 0
                                    ? const Color(0xFF3B82F6)
                                    : (index == 1
                                        ? const Color(0xFF10B981)
                                        : (index == 2 ? const Color(0xFFF59E0B) : const Color(0xFF8B5CF6))),
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: entries[index].controller,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                  decoration: InputDecoration(
                                    labelText: isMe ? 'Member 1 (You / Organizer)' : 'Member ${index + 1} Name',
                                    hintText: isMe ? 'Your Name' : 'Companion name, e.g. Priya',
                                    filled: true,
                                    fillColor: isDark ? const Color(0xFF1C2A3A) : const Color(0xFFF3F4F6),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide.none,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  ),
                                ),
                              ),
                              if (!isMe && entries.length > 1)
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 20),
                                  onPressed: () {
                                    setSheetState(() {
                                      final removed = entries.removeAt(index);
                                      if (removed.userId != null) {
                                        removedUserIds.add(removed.userId!);
                                      }
                                      final rawName = removed.controller.text.trim();
                                      if (rawName.isNotEmpty) {
                                        removedNames.add(rawName);
                                      }
                                      removed.controller.dispose();
                                    });
                                  },
                                ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 6),
                      TextButton.icon(
                        onPressed: () {
                          setSheetState(() {
                            entries.add(
                              _CompanionEntry(
                                controller: TextEditingController(text: 'Companion ${entries.length + 1}'),
                                isOrganizer: false,
                              ),
                            );
                          });
                        },
                        icon: const Icon(Icons.add_circle_outline, size: 18),
                        label: const Text('Add Another Companion', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () async {
                            final names = entries
                                .map((c) => c.controller.text.trim())
                                .where((n) => n.isNotEmpty)
                                .toList();
                            if (names.isEmpty) {
                              names.add(myDefaultName);
                            }
                            final myEnteredName = names.first;
                            final newCount = names.length.clamp(1, AppConstants.maxCrewMembers);

                            // 1. Permanently delete removed members from Supabase trip_members
                            if (SupabaseService.isInitialized) {
                              for (final uid in removedUserIds) {
                                try {
                                  await SupabaseService.client
                                      .from('trip_members')
                                      .delete()
                                      .eq('trip_id', trip.id)
                                      .eq('user_id', uid);
                                } catch (_) {}
                              }
                              // Also delete by matching display name if uid was unknown
                              for (final rName in removedNames) {
                                try {
                                  final prof = await SupabaseService.client
                                      .from('profiles')
                                      .select('id')
                                      .eq('display_name', rName)
                                      .maybeSingle();
                                  if (prof != null) {
                                    final pid = prof['id']?.toString();
                                    if (pid != null && pid != authUser?.uid) {
                                      await SupabaseService.client
                                          .from('trip_members')
                                          .delete()
                                          .eq('trip_id', trip.id)
                                          .eq('user_id', pid);
                                      removedUserIds.add(pid);
                                    }
                                  }
                                } catch (_) {}
                              }
                              // 2. Update trip member_count in Supabase
                              try {
                                await SupabaseService.client
                                    .from('trips')
                                    .update({
                                      'member_count': newCount,
                                      'updated_at': DateTime.now().toIso8601String(),
                                    })
                                    .eq('id', trip.id);
                              } catch (_) {}
                            }

                            // 3. Update tripsProvider local state so the entire app is aware of the new count
                            ref.read(tripsProvider.notifier).updateLocalTripMemberCount(trip.id, newCount);

                            // 4. Save updated names and persistent blacklists in SharedPreferences
                            try {
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.setStringList('trip_crew_names_${trip.id}', names);
                              await prefs.setString('user_custom_name', myEnteredName);

                              final blacklistedUids = prefs.getStringList('removed_crew_uids_${trip.id}') ?? [];
                              blacklistedUids.addAll(removedUserIds);
                              await prefs.setStringList('removed_crew_uids_${trip.id}', blacklistedUids.toSet().toList());

                              final blacklistedNames = prefs.getStringList('removed_crew_names_${trip.id}') ?? [];
                              blacklistedNames.addAll(removedNames);
                              await prefs.setStringList('removed_crew_names_${trip.id}', blacklistedNames.toSet().toList());
                            } catch (_) {}

                            ref.read(authProvider.notifier).updateProfile(name: myEnteredName);
                            if (SupabaseService.isInitialized) {
                              try {
                                final uid = ref.read(authProvider).user?.uid;
                                if (uid != null) {
                                  await SupabaseService.client.from('profiles').upsert({
                                    'id': uid,
                                    'display_name': myEnteredName,
                                    'updated_at': DateTime.now().toIso8601String(),
                                  });
                                }
                              } catch (_) {}
                            }

                            if (mounted) {
                              setState(() {
                                _tripCrewNames = names;
                                _cachedUserName = myEnteredName;
                              });
                              Navigator.of(sheetContext, rootNavigator: true).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Crew updated: ${names.join(", ")} 🎉'),
                                  backgroundColor: const Color(0xFF10B981),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFFFE600),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: const Text('Save Crew Names', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showChangeStatusDialog(BuildContext context, TripModel trip) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final isDark = theme.brightness == Brightness.dark;
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F1B2B) : Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 20, offset: Offset(0, -4)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Update Trip Status',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'Set whether "${trip.destination}" was carried out or cancelled.',
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 18),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF10B981),
                    child: Icon(Icons.check, color: Colors.white, size: 18),
                  ),
                  title: const Text('Carried Out ✓', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Trip took place successfully'),
                  trailing: trip.isCompleted ? const Icon(Icons.check_circle, color: Color(0xFF10B981)) : null,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  tileColor: trip.isCompleted ? const Color(0xFF10B981).withValues(alpha: 0.1) : null,
                  onTap: () async {
                    setState(() {
                      _tripStatusOverrides[trip.id] = 'completed';
                    });
                    try {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('trip_status_${trip.id}', 'completed');
                    } catch (_) {}
                    Navigator.of(sheetContext, rootNavigator: true).pop();
                    await ref.read(tripsProvider.notifier).updateTripStatus(trip.id, 'completed');
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Trip marked as Carried Out ✓'),
                          backgroundColor: Color(0xFF10B981),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFEF4444),
                    child: Icon(Icons.close, color: Colors.white, size: 18),
                  ),
                  title: const Text('Not Carried Out / Cancelled ✕', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Trip did not happen or was dropped'),
                  trailing: trip.isCancelled ? const Icon(Icons.check_circle, color: Color(0xFFEF4444)) : null,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  tileColor: trip.isCancelled ? const Color(0xFFEF4444).withValues(alpha: 0.1) : null,
                  onTap: () async {
                    setState(() {
                      _tripStatusOverrides[trip.id] = 'cancelled';
                    });
                    try {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('trip_status_${trip.id}', 'cancelled');
                    } catch (_) {}
                    Navigator.of(sheetContext, rootNavigator: true).pop();
                    await ref.read(tripsProvider.notifier).updateTripStatus(trip.id, 'cancelled');
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Trip marked as Not Carried Out / Cancelled ✕'),
                          backgroundColor: Color(0xFFEF4444),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showTripPickerSheet(BuildContext context) {
    final tripsState = ref.read(tripsProvider);
    final allTrips = tripsState.trips;
    final activeTrip = tripsState.activeTrip;

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final isDark = theme.brightness == Brightness.dark;

        final ongoing = allTrips.where((t) => t.isOngoing && !t.isCancelled).toList();
        final upcoming = allTrips.where((t) => t.isUpcoming && !t.isCancelled).toList();
        final past = allTrips.where((t) => t.isPast || t.isCompleted || t.isCancelled).toList();

        return SafeArea(
          top: false,
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F1B2B) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.75,
            ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Your Trips',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      context.push('/create-trip');
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New Trip', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (ongoing.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          'ACTIVE / ONGOING',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF10B981), letterSpacing: 0.8),
                        ),
                      ),
                      ...ongoing.map((t) => _buildTripPickerItem(t, activeTrip?.id == t.id)),
                    ],
                    if (upcoming.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          'UPCOMING',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF38BDF8), letterSpacing: 0.8),
                        ),
                      ),
                      ...upcoming.map((t) => _buildTripPickerItem(t, activeTrip?.id == t.id)),
                    ],
                    if (past.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          'PAST TRIPS',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFF59E0B), letterSpacing: 0.8),
                        ),
                      ),
                      ...past.map((t) => _buildTripPickerItem(t, activeTrip?.id == t.id)),
                    ],
                    if (allTrips.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(
                          child: Text('No trips found. Plan your first trip!'),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

  Widget _buildTripPickerItem(TripModel trip, bool isSelected) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFF258CF4).withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected ? const Color(0xFF258CF4) : Colors.white.withValues(alpha: 0.1),
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: ListTile(
        onTap: () {
          ref.read(tripsProvider.notifier).setActiveTrip(trip.id);
          Navigator.of(context, rootNavigator: true).pop();
        },
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: trip.isCancelled
                ? const Color(0xFFEF4444).withValues(alpha: 0.2)
                : (trip.isCompleted
                    ? const Color(0xFF10B981).withValues(alpha: 0.2)
                    : (trip.isOngoing ? const Color(0xFF10B981) : const Color(0xFFFFE600))),
            shape: BoxShape.circle,
          ),
          child: Icon(
            trip.isCancelled
                ? Icons.cancel_outlined
                : (trip.isCompleted
                    ? Icons.check
                    : (trip.isOngoing ? Icons.near_me : Icons.flight_takeoff)),
            color: trip.isOngoing ? Colors.white : Colors.black87,
            size: 16,
          ),
        ),
        title: Text(
          trip.startingPlace.isNotEmpty ? '${trip.startingPlace} → ${trip.destination}' : trip.name,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
        subtitle: Text(
          '${DateFormat('dd MMM').format(trip.startDate)} - ${DateFormat('dd MMM').format(trip.endDate)} · ${trip.displayStatusLabel}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: isSelected
            ? const Icon(Icons.check_circle, color: Color(0xFF258CF4), size: 20)
            : const Icon(Icons.chevron_right, size: 18),
      ),
    );
  }

}

/// Dynamic, live-updating bottom sheet for crew notifications that reacts to real-time events immediately
class _CrewUpdatesSheet extends StatefulWidget {
  final String tripId;
  final List<_CrewNotification> initialNotifications;
  final ValueChanged<List<_CrewNotification>> onNotificationsUpdated;

  const _CrewUpdatesSheet({
    required this.tripId,
    required this.initialNotifications,
    required this.onNotificationsUpdated,
  });

  @override
  State<_CrewUpdatesSheet> createState() => _CrewUpdatesSheetState();
}

class _CrewUpdatesSheetState extends State<_CrewUpdatesSheet> {
  late List<_CrewNotification> _items;
  bool _isLoading = false;
  StreamSubscription? _eventSub;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.initialNotifications);
    _refreshNotifications();

    // Listen to live events so any new pulse, chat, memory or itinerary change updates sheet live!
    _eventSub = TripNotificationWatcher.instance.onNewEventStream.listen((_) {
      if (mounted) {
        _refreshNotifications();
      }
    });
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }

  Future<void> _refreshNotifications() async {
    if (!mounted || !SupabaseService.isInitialized) return;
    setState(() => _isLoading = true);

    try {
      final notifs = <_CrewNotification>[];

      // 1. Members
      try {
        final members = await SupabaseService.client
            .from('trip_members')
            .select('user_name, joined_at')
            .eq('trip_id', widget.tripId)
            .order('joined_at', ascending: false)
            .limit(3);
        for (final m in members) {
          final name = m['user_name'] as String? ?? 'A companion';
          notifs.add(_CrewNotification(
            id: 'member_${m['joined_at']}',
            title: 'Crew Member Joined',
            subtitle: '$name joined the crew',
            timeAgo: _formatTimeAgoStatic(m['joined_at']),
            icon: Icons.person_add_rounded,
            iconColor: const Color(0xFF10B981),
            route: '/crew',
          ));
        }
      } catch (_) {}

      // 2. Itinerary stops
      try {
        final stops = await SupabaseService.client
            .from('itinerary_items')
            .select('id, title, day_number, time, created_at')
            .eq('trip_id', widget.tripId)
            .order('created_at', ascending: false)
            .limit(4);
        for (final s in stops) {
          final title = s['title'] as String? ?? 'New stop';
          final day = s['day_number'] ?? 1;
          final time = s['time'] as String? ?? '';
          notifs.add(_CrewNotification(
            id: 'itinerary_${s['id']}',
            title: 'Itinerary Stop Added',
            subtitle: time.isNotEmpty ? '$title · Day $day ($time)' : '$title · Day $day',
            timeAgo: _formatTimeAgoStatic(s['created_at']),
            icon: Icons.place_rounded,
            iconColor: const Color(0xFFEF4444),
            route: '/itinerary',
          ));
        }
      } catch (_) {}

      // 3. Memories
      try {
        final memories = await SupabaseService.client
            .from('memories')
            .select('id, user_name, photographer_name, caption, created_at')
            .eq('trip_id', widget.tripId)
            .order('created_at', ascending: false)
            .limit(3);
        for (final item in memories) {
          final uName = (item['photographer_name'] ?? item['user_name']) as String? ?? 'Crew member';
          final cap = item['caption'] as String? ?? 'Shared a photo';
          notifs.add(_CrewNotification(
            id: 'mem_${item['id']}',
            title: 'New Memory Photo',
            subtitle: '$uName: $cap',
            timeAgo: _formatTimeAgoStatic(item['created_at']),
            icon: Icons.photo_library_rounded,
            iconColor: const Color(0xFF8B5CF6),
            route: '/memories',
          ));
        }
      } catch (_) {}

      // 4. Pulses / Check-ins (Active & Recent)
      try {
        final pulses = await SupabaseService.client
            .from('trip_pulses')
            .select('id, user_name, pulse_type, created_at')
            .eq('trip_id', widget.tripId)
            .order('created_at', ascending: false)
            .limit(5);
        for (final item in pulses) {
          final uName = item['user_name'] as String? ?? 'Crew member';
          final status = item['pulse_type'] as String? ?? 'Checked in';
          notifs.add(_CrewNotification(
            id: 'pulse_${item['id']}_${item['created_at']}',
            title: 'Live Crew Pulse',
            subtitle: '$uName: $status',
            timeAgo: _formatTimeAgoStatic(item['created_at']),
            icon: Icons.favorite_rounded,
            iconColor: const Color(0xFFEC4899),
            route: '/pulse',
          ));
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _items = notifs;
          _isLoading = false;
        });
        widget.onNotificationsUpdated(notifs);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  static String _formatTimeAgoStatic(dynamic timestamp) {
    if (timestamp == null) return 'recently';
    try {
      final dt = DateTime.parse(timestamp.toString()).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return 'recently';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131D2D) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          // Drag handle
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text(
                      'Crew Updates',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (_items.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFE600),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_items.length} new',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ],
                    if (_isLoading) ...[
                      const SizedBox(width: 8),
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _items.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.notifications_none_rounded,
                            size: 48,
                            color: theme.colorScheme.primary.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'All caught up!',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'No recent notifications. As your crew logs expenses, adds itinerary stops, and shares photos, updates will appear here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _refreshNotifications,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      itemCount: _items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final notif = _items[i];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: notif.iconColor.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              notif.icon,
                              color: notif.iconColor,
                              size: 20,
                            ),
                          ),
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                notif.title,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                notif.timeAgo,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              notif.subtitle,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          trailing: const Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: Colors.grey,
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            context.push(notif.route);
                          },
                        );
                      },
                    ),
                  ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
