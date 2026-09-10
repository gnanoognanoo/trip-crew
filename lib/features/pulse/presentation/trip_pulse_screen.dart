import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/core/services/analytics_service.dart';
import 'package:tripcrew/core/services/firebase_service.dart';
import 'package:tripcrew/features/auth/providers/auth_provider.dart';
import 'package:tripcrew/features/pulse/models/trip_pulse.dart';
import 'package:tripcrew/features/trips/providers/trips_provider.dart';

/// Screen 15: Trip Pulse screen connected to real Firestore trips/{tripId}/pulses.
class TripPulseScreen extends ConsumerStatefulWidget {
  const TripPulseScreen({super.key});

  @override
  ConsumerState<TripPulseScreen> createState() => _TripPulseScreenState();
}

class _TripPulseScreenState extends ConsumerState<TripPulseScreen> {
  StreamSubscription? _pulseSub;
  String? _myPulse;
  final Map<String, int> _pulseCounts = {};
  bool _isLoading = true;

  final List<Map<String, dynamic>> _pulseOptions = const [
    {
      'title': 'Hungry',
      'icon': Icons.restaurant_rounded,
      'color': Color(0xFFF97316),
      'emoji': '🍕',
    },
    {
      'title': 'Need Coffee',
      'icon': Icons.local_cafe_rounded,
      'color': Color(0xFF3B82F6),
      'emoji': '☕',
    },
    {
      'title': 'Need Fuel',
      'icon': Icons.local_gas_station_rounded,
      'color': Color(0xFF10B981),
      'emoji': '⛽',
    },
    {
      'title': 'Restroom',
      'icon': Icons.wc_rounded,
      'color': Color(0xFF06B6D4),
      'emoji': '🚻',
    },
    {
      'title': 'Tired',
      'icon': Icons.bed_rounded,
      'color': Color(0xFFD97706),
      'emoji': '🥱',
    },
    {
      'title': 'Want Photos',
      'icon': Icons.camera_alt_rounded,
      'color': Color(0xFF8B5CF6),
      'emoji': '📸',
    },
    {
      'title': 'Need Break',
      'icon': Icons.pan_tool_rounded,
      'color': Color(0xFFE11D48),
      'emoji': '🛑',
    },
    {
      'title': 'Emergency',
      'icon': Icons.warning_amber_rounded,
      'color': Color(0xFFDC2626),
      'emoji': '🚨',
    },
  ];

  @override
  void initState() {
    super.initState();
    _listenToPulses();
  }

  void _listenToPulses() {
    final activeTrip = ref.read(activeTripProvider);
    final user = ref.read(authProvider).user;

    if (activeTrip == null) {
      setState(() => _isLoading = false);
      return;
    }

    if (FirebaseService.isInitialized) {
      _pulseSub = FirebaseFirestore.instance
          .collection('trips')
          .doc(activeTrip.id)
          .collection('pulses')
          .snapshots()
          .listen(
            (snapshot) {
              final counts = <String, int>{};
              String? myCurrent;

              for (final doc in snapshot.docs) {
                final pulse = TripPulse.fromMap(doc.data(), doc.id);
                // Only count pulses from the last 2 hours
                if (DateTime.now().difference(pulse.timestamp).inHours < 2) {
                  counts[pulse.pulseType] = (counts[pulse.pulseType] ?? 0) + 1;
                  if (doc.id == user?.uid) {
                    myCurrent = pulse.pulseType;
                  }
                }
              }

              if (mounted) {
                setState(() {
                  _pulseCounts.clear();
                  _pulseCounts.addAll(counts);
                  _myPulse = myCurrent;
                  _isLoading = false;
                });
              }
            },
            onError: (_) {
              if (mounted) setState(() => _isLoading = false);
            },
          );
    } else {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _pulseSub?.cancel();
    super.dispose();
  }

  void _selectPulse(String title, String tripId) async {
    final user = ref.read(authProvider).user;
    setState(() => _myPulse = title);

    if (FirebaseService.isInitialized && user != null) {
      await FirebaseFirestore.instance
          .collection('trips')
          .doc(tripId)
          .collection('pulses')
          .doc(user.uid)
          .set({
            'uid': user.uid,
            'memberName': user.name,
            'pulseType': title,
            'timestamp': FieldValue.serverTimestamp(),
          });
    }

    await AnalyticsService.logPulseSent(tripId, title);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Pulse updated: $title shared with crew!'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.spaceLg,
                AppConstants.spaceSm,
                AppConstants.spaceLg,
                AppConstants.spaceMd,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'How are you feeling?',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tap a pulse to share your real-time need with your crew in ${activeTrip.name}.',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

            // 2x4 Pulse Options Grid
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : GridView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppConstants.spaceLg,
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
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
                          onTap: () =>
                              _selectPulse(opt['title'], activeTrip.id),
                          borderRadius: BorderRadius.circular(
                            AppConstants.radiusLg,
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? color.withValues(alpha: 0.18)
                                  : theme.colorScheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(
                                AppConstants.radiusLg,
                              ),
                              border: Border.all(
                                color: isSelected
                                    ? color
                                    : theme.colorScheme.outlineVariant,
                                width: isSelected ? 2.0 : 1.0,
                              ),
                            ),
                            child: Stack(
                              children: [
                                Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: color.withValues(alpha: 0.15),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          opt['icon'],
                                          color: color,
                                          size: 26,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        opt['title'],
                                        style: TextStyle(
                                          fontWeight: isSelected
                                              ? FontWeight.w800
                                              : FontWeight.w600,
                                          fontSize: 14,
                                          color: isSelected
                                              ? color
                                              : theme.colorScheme.onSurface,
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
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: color,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        '$count',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
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

            // Bottom "Crew Pulse" Dynamic Summary
            Container(
              padding: const EdgeInsets.all(AppConstants.spaceLg),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppConstants.radiusXl),
                  topRight: Radius.circular(AppConstants.radiusXl),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Crew Pulse Status',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_pulseCounts.isEmpty)
                    Text(
                      'No active pulses in the last 2 hours. Tap a card above to check in.',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: _pulseCounts.entries.map((entry) {
                        final opt = _pulseOptions.firstWhere(
                          (o) => o['title'] == entry.key,
                          orElse: () => {'emoji': '📍'},
                        );
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Text(
                            '${opt['emoji']} ${entry.value} ${entry.key.toLowerCase()}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
