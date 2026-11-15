import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tripcrew/core/services/analytics_service.dart';
import 'package:tripcrew/core/services/supabase_service.dart';
import 'package:tripcrew/core/services/trip_notification_watcher.dart';
import 'package:tripcrew/features/auth/providers/auth_provider.dart';
import 'package:tripcrew/features/pulse/models/trip_pulse.dart';
import 'package:tripcrew/features/trips/providers/trips_provider.dart';

/// Representation of an active crew member pulse for the live activity feed
class _ActiveMemberPulse {
  final String userId;
  final String memberName;
  final String pulseType;
  final String emoji;
  final Color color;
  final DateTime createdAt;
  final bool isMe;

  const _ActiveMemberPulse({
    required this.userId,
    required this.memberName,
    required this.pulseType,
    required this.emoji,
    required this.color,
    required this.createdAt,
    required this.isMe,
  });
}

/// Screen 15: Trip Pulse screen connected to real Supabase trip_pulses table.
/// Allows members to broadcast and view current needs (Hungry, Break, Tired, Emergency, etc.)
class TripPulseScreen extends ConsumerStatefulWidget {
  const TripPulseScreen({super.key});

  @override
  ConsumerState<TripPulseScreen> createState() => _TripPulseScreenState();
}

class _TripPulseScreenState extends ConsumerState<TripPulseScreen> {
  StreamSubscription? _pulseSub;
  StreamSubscription? _watcherSub;
  Timer? _pollingTimer;
  String? _myPulse;
  final Map<String, int> _pulseCounts = {};
  final List<_ActiveMemberPulse> _memberPulses = [];

  final List<Map<String, dynamic>> _pulseOptions = const [
    {
      'type': PulseType.hungry,
      'title': 'Hungry',
      'icon': Icons.restaurant_rounded,
      'color': Color(0xFFF97316),
      'emoji': '🍔',
      'durationMinutes': 60,
    },
    {
      'type': PulseType.needBreak,
      'title': 'Need a Break',
      'icon': Icons.local_cafe_rounded,
      'color': Color(0xFF3B82F6),
      'emoji': '☕',
      'durationMinutes': 30,
    },
    {
      'type': PulseType.restroom,
      'title': 'Restroom',
      'icon': Icons.wc_rounded,
      'color': Color(0xFF06B6D4),
      'emoji': '🚻',
      'durationMinutes': 30,
    },
    {
      'type': PulseType.needFuel,
      'title': 'Need Fuel',
      'icon': Icons.local_gas_station_rounded,
      'color': Color(0xFF10B981),
      'emoji': '⛽',
      'durationMinutes': 60,
    },
    {
      'type': PulseType.tired,
      'title': 'Tired',
      'icon': Icons.bed_rounded,
      'color': Color(0xFF8B5CF6),
      'emoji': '😴',
      'durationMinutes': 60,
    },
    {
      'type': PulseType.wantPhotos,
      'title': 'Want Photos',
      'icon': Icons.camera_alt_rounded,
      'color': Color(0xFFEC4899),
      'emoji': '📸',
      'durationMinutes': 60,
    },
    {
      'type': PulseType.emergency,
      'title': 'Emergency',
      'icon': Icons.warning_amber_rounded,
      'color': Color(0xFFDC2626),
      'emoji': '🚨',
      'durationMinutes': 120,
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadLocalPulseCache();
    _fetchPulses();
    _subscribeToPulseStream();

    // Listen to real-time notification watcher events for instantaneous pulse sync
    _watcherSub = TripNotificationWatcher.instance.onNewEventStream.listen((event) {
      if (event == 'pulse' && mounted) {
        _fetchPulses(silent: true);
      }
    });

    // Regular polling fallback every 8 seconds to ensure crew sync
    _pollingTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _fetchPulses(silent: true);
    });
  }

  @override
  void dispose() {
    _pulseSub?.cancel();
    _watcherSub?.cancel();
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadLocalPulseCache() async {
    final activeTrip = ref.read(activeTripProvider);
    if (activeTrip == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('my_pulse_${activeTrip.id}');
      if (saved != null && mounted) {
        setState(() => _myPulse = saved);
      }
    } catch (_) {}
  }

  Future<String> _resolveCurrentUserId() async {
    final user = ref.read(authProvider).user;
    if (user != null && user.uid.isNotEmpty) return user.uid;
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUid = prefs.getString('persistent_traveler_uid');
      if (savedUid != null && savedUid.isNotEmpty) return savedUid;
    } catch (_) {}
    return 'traveler_${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<String> _resolveCurrentUserName() async {
    final user = ref.read(authProvider).user;
    if (user != null && user.name.isNotEmpty && user.name != 'Traveler') {
      return user.name;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final customName = prefs.getString('user_custom_name');
      if (customName != null && customName.isNotEmpty) return customName;
      final savedName = prefs.getString('persistent_traveler_name');
      if (savedName != null && savedName.isNotEmpty) return savedName;
    } catch (_) {}
    return 'Traveler';
  }

  Future<void> _fetchPulses({bool silent = false}) async {
    final activeTrip = ref.read(activeTripProvider);
    if (activeTrip == null) return;

    final myUid = await _resolveCurrentUserId();

    if (SupabaseService.isInitialized) {
      try {
        final data = await SupabaseService.client
            .from('trip_pulses')
            .select()
            .eq('trip_id', activeTrip.id)
            .eq('is_active', true)
            .order('created_at', ascending: false);

        final counts = <String, int>{};
        final members = <_ActiveMemberPulse>[];
        String? currentMyPulse = _myPulse;

        for (final row in data) {
          final pulse = TripPulse.fromMap(row, (row['user_id'] ?? row['uid']) as String? ?? '');
          if (pulse.isCurrentlyActive) {
            counts[pulse.pulseType] = (counts[pulse.pulseType] ?? 0) + 1;
            final isMe = (pulse.uid == myUid);
            if (isMe) {
              currentMyPulse = pulse.pulseType;
            }

            final opt = _pulseOptions.firstWhere(
              (o) => o['title'] == pulse.pulseType,
              orElse: () => {
                'color': const Color(0xFF10B981),
                'emoji': pulse.emoji,
              },
            );

            members.add(
              _ActiveMemberPulse(
                userId: pulse.uid,
                memberName: isMe ? '${pulse.memberName} (You)' : pulse.memberName,
                pulseType: pulse.pulseType,
                emoji: opt['emoji'] as String? ?? '📍',
                color: opt['color'] as Color? ?? const Color(0xFF10B981),
                createdAt: pulse.createdAt,
                isMe: isMe,
              ),
            );
          }
        }

        if (mounted) {
          setState(() {
            _pulseCounts.clear();
            _pulseCounts.addAll(counts);
            _memberPulses.clear();
            _memberPulses.addAll(members);
            _myPulse = currentMyPulse;
          });
        }
      } catch (e) {
        // Fallback to local cache without blocking user
      }
    }
  }

  void _subscribeToPulseStream() {
    final activeTrip = ref.read(activeTripProvider);
    if (activeTrip == null || !SupabaseService.isInitialized) return;

    try {
      _pulseSub = SupabaseService.client
          .from('trip_pulses')
          .stream(primaryKey: ['id'])
          .eq('trip_id', activeTrip.id)
          .listen(
            (_) => _fetchPulses(silent: true),
            onError: (_) {},
          );
    } catch (_) {}
  }

  Future<bool> _confirmEmergencyPulse() async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.warning_amber_rounded,
          color: Color(0xFFDC2626),
          size: 40,
        ),
        title: const Text(
          'Send Emergency Pulse to your crew?',
          textAlign: TextAlign.center,
        ),
        content: const Text(
          'This sends an urgent in-app alert to all crew members.\n\n'
          'Note: This does NOT contact police, ambulance, or emergency services.',
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send Alert'),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  Future<void> _selectPulse(Map<String, dynamic> opt, String tripId) async {
    final PulseType pType = opt['type'] as PulseType;
    final String title = opt['title'] as String;

    if (pType == PulseType.emergency) {
      final confirmed = await _confirmEmergencyPulse();
      if (!confirmed || !mounted) return;
    }

    final myUid = await _resolveCurrentUserId();
    final myName = await _resolveCurrentUserName();

    setState(() => _myPulse = title);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('my_pulse_$tripId', title);
    } catch (_) {}

    final nowUtc = DateTime.now().toUtc();
    final expiresAtUtc = nowUtc.add(pType.defaultDuration);

    if (SupabaseService.isInitialized) {
      try {
        // Deactivate previous active pulses for this user
        await SupabaseService.client
            .from('trip_pulses')
            .update({'is_active': false})
            .eq('trip_id', tripId)
            .eq('user_id', myUid);

        // Insert new unique pulse row so streams and notification watchers detect new event immediately
        final newPulseId = 'pulse_${tripId}_${myUid}_${DateTime.now().millisecondsSinceEpoch}';
        final payload = {
          'id': newPulseId,
          'trip_id': tripId,
          'user_id': myUid,
          'user_name': myName,
          'pulse_type': title,
          'type': pType.key,
          'is_active': true,
          'created_at': nowUtc.toIso8601String(),
          'expires_at': expiresAtUtc.toIso8601String(),
        };

        await SupabaseService.client.from('trip_pulses').insert(payload);
        TripNotificationWatcher.instance.notifyLocalEvent('pulse');
      } catch (e) {
        debugPrint('[TripPulse] Error saving pulse: $e');
      }
    }

    await AnalyticsService.logPulseSent(tripId, title);
    await _fetchPulses(silent: true);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pulse shared: ${opt['emoji']} $title broadcasted to crew!',
          ),
          backgroundColor: opt['color'] as Color?,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _clearPulse(String tripId) async {
    final myUid = await _resolveCurrentUserId();
    setState(() => _myPulse = null);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('my_pulse_$tripId');
    } catch (_) {}

    if (SupabaseService.isInitialized) {
      try {
        await SupabaseService.client
            .from('trip_pulses')
            .update({'is_active': false})
            .eq('trip_id', tripId)
            .eq('user_id', myUid);
        TripNotificationWatcher.instance.notifyLocalEvent('pulse');
      } catch (_) {}
    }
    await _fetchPulses(silent: true);

    await _fetchPulses(silent: true);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pulse status cleared'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  String _formatExactTime(DateTime dt) {
    return DateFormat('hh:mm a').format(dt.toLocal());
  }

  String _formatRelativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inSeconds < 45) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('dd MMM').format(dt.toLocal());
  }

  String _formatPulseSubtitle(String pulseType) {
    final lower = pulseType.toLowerCase().trim();
    if (lower == 'want photos') {
      return 'Wants photos taken 📸';
    } else if (lower == 'need a break' || lower == 'need break') {
      return 'Needs a short break ☕';
    } else if (lower == 'need fuel') {
      return 'Needs fuel / gas station ⛽';
    } else if (lower == 'hungry') {
      return 'Feeling hungry 🍔';
    } else if (lower == 'tired') {
      return 'Feeling tired 😴';
    } else if (lower == 'restroom') {
      return 'Needs a restroom 🚻';
    } else if (lower == 'emergency') {
      return 'Emergency alert 🚨';
    } else if (lower.startsWith('need') || lower.startsWith('want') || lower.startsWith('feeling')) {
      return pulseType;
    }
    return 'Needs $pulseType';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final activeTrip = ref.watch(activeTripProvider);

    if (activeTrip == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Trip Pulse')),
        body: const Center(child: Text('No active trip selected.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip Pulse'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/workspace');
            }
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Pulses',
            onPressed: () => _fetchPulses(),
          ),
          if (_myPulse != null)
            TextButton.icon(
              onPressed: () => _clearPulse(activeTrip.id),
              icon: const Icon(Icons.clear_rounded, size: 16),
              label: const Text('Clear'),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Card
              Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      isDark ? const Color(0xFF1E2E42) : const Color(0xFFF1F5F9),
                      isDark ? const Color(0xFF162332) : const Color(0xFFE2E8F0),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark ? Colors.white12 : const Color(0xFFCBD5E1),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEC4899).withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.favorite_rounded,
                        color: Color(0xFFEC4899),
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _myPulse != null
                                ? 'Your Current Need: $_myPulse'
                                : 'How are you feeling?',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _myPulse != null
                                ? 'Shared live with your crew in ${activeTrip.name}.'
                                : 'Tap a pulse below to notify your crew instantly.',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Pulse Options Grid
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Select Your Current Need:',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 10),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.4,
                  ),
                  itemCount: _pulseOptions.length,
                  itemBuilder: (context, index) {
                    final opt = _pulseOptions[index];
                    final isSelected = _myPulse == opt['title'];
                    final Color color = opt['color'];
                    final count = _pulseCounts[opt['title']] ?? 0;

                    return InkWell(
                      onTap: () => _selectPulse(opt, activeTrip.id),
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected
                              ? color.withValues(alpha: 0.22)
                              : (isDark ? const Color(0xFF162332) : Colors.white),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isSelected ? color : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                            width: isSelected ? 2.5 : 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Stack(
                          children: [
                            Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(opt['emoji'], style: const TextStyle(fontSize: 30)),
                                  const SizedBox(height: 6),
                                  Text(
                                    opt['title'],
                                    style: TextStyle(
                                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                      fontSize: 14,
                                      color: isSelected ? color : (isDark ? Colors.white : Colors.black87),
                                    ),
                                  ),
                                  Text(
                                    '${opt['durationMinutes']}m active',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isDark ? Colors.white54 : Colors.black45,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (count > 0)
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '$count',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 20),

              // Live Crew Activity Section
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF162332) : Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 10,
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
                        const Text(
                          'Live Crew Pulse Feed',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF10B981),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              const Text(
                                'Live Synced',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (_memberPulses.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: Text(
                            'No pulses broadcasted yet.\nTap an option above to notify your crew!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: isDark ? Colors.white60 : Colors.black45,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _memberPulses.length,
                        separatorBuilder: (_, __) => Divider(
                          color: isDark ? Colors.white12 : const Color(0xFFF1F5F9),
                          height: 16,
                        ),
                        itemBuilder: (context, idx) {
                          final p = _memberPulses[idx];
                          return Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: p.color.withValues(alpha: 0.2),
                                child: Text(p.emoji, style: const TextStyle(fontSize: 16)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p.memberName,
                                      style: TextStyle(
                                        fontWeight: p.isMe ? FontWeight.w800 : FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      _formatPulseSubtitle(p.pulseType),
                                      style: TextStyle(
                                        color: p.color,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _formatExactTime(p.createdAt),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _formatRelativeTime(p.createdAt),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                      color: isDark ? Colors.white54 : Colors.black45,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}
