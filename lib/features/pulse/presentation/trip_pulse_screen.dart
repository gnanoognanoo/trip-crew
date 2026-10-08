import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/core/services/analytics_service.dart';
import 'package:tripcrew/core/services/supabase_service.dart';
import 'package:tripcrew/core/widgets/app_error_state.dart';
import 'package:tripcrew/features/auth/providers/auth_provider.dart';
import 'package:tripcrew/features/pulse/models/trip_pulse.dart';
import 'package:tripcrew/features/trips/providers/trips_provider.dart';

/// Screen 15: Trip Pulse screen connected to real Supabase trip_pulses table.
/// Allows members to broadcast and view current needs (Hungry, Break, Tired, Emergency, etc.)
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
  String? _errorMessage;

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
    _listenToPulses();
  }

  void _listenToPulses() {
    final activeTrip = ref.read(activeTripProvider);
    final user = ref.read(authProvider).user;

    if (activeTrip == null) {
      setState(() => _isLoading = false);
      return;
    }

    if (SupabaseService.isInitialized) {
      _pulseSub = SupabaseService.client
          .from('trip_pulses')
          .stream(primaryKey: ['id'])
          .eq('trip_id', activeTrip.id)
          .listen(
            (data) {
              final counts = <String, int>{};
              String? myCurrent;

              for (final row in data) {
                final pulse = TripPulse.fromMap(row, (row['user_id'] ?? row['uid']) as String? ?? '');
                if (pulse.isCurrentlyActive) {
                  counts[pulse.pulseType] = (counts[pulse.pulseType] ?? 0) + 1;
                  if (pulse.uid == user?.uid) {
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
                  _errorMessage = null;
                });
              }
            },
            onError: (e) {
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _errorMessage =
                      'Could not load pulse data. Check your connection.';
                });
              }
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
          'This sends an urgent in-app alert to your crew members.\n\n'
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
            child: const Text('Send'),
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

    final user = ref.read(authProvider).user;
    setState(() => _myPulse = title);

    final now = DateTime.now();
    final expiresAt = now.add(pType.defaultDuration);

    if (SupabaseService.isInitialized && user != null) {
      final pulse = TripPulse(
        uid: user.uid,
        memberName: user.name,
        pulseType: title,
        type: pType.key,
        createdAt: now,
        expiresAt: expiresAt,
        isActive: true,
      );

      await SupabaseService.client
          .from('trip_pulses')
          .upsert(pulse.toMap(tripId: tripId));
    }

    await AnalyticsService.logPulseSent(tripId, title);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pulse updated: ${opt['emoji']} $title shared with crew!',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _clearPulse(String tripId) async {
    final user = ref.read(authProvider).user;
    setState(() => _myPulse = null);

    if (SupabaseService.isInitialized && user != null) {
      await SupabaseService.client
          .from('trip_pulses')
          .delete()
          .eq('trip_id', tripId)
          .eq('user_id', user.uid);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pulse status cleared'),
          duration: Duration(seconds: 2),
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
        actions: [
          if (_myPulse != null)
            TextButton.icon(
              onPressed: () => _clearPulse(activeTrip.id),
              icon: const Icon(Icons.clear_rounded, size: 16),
              label: const Text('Clear Status'),
            ),
        ],
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
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
                ],
              ),
            ),

            // Pulse Options Grid
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                  ? AppErrorState(
                      title: 'Could not load pulse data',
                      message: _errorMessage!,
                      onRetry: () {
                        setState(() {
                          _isLoading = true;
                          _errorMessage = null;
                        });
                        _listenToPulses();
                      },
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppConstants.spaceLg,
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 1.35,
                          ),
                      itemCount: _pulseOptions.length,
                      itemBuilder: (context, index) {
                        final opt = _pulseOptions[index];
                        final isSelected = _myPulse == opt['title'];
                        final Color color = opt['color'];
                        final count = _pulseCounts[opt['title']] ?? 0;

                        return InkWell(
                          onTap: () => _selectPulse(opt, activeTrip.id),
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
                                width: isSelected ? 2.5 : 1.0,
                              ),
                            ),
                            child: Stack(
                              children: [
                                Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        opt['emoji'],
                                        style: const TextStyle(fontSize: 32),
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
                                      Text(
                                        '${opt['durationMinutes']}m expiry',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: theme
                                              .colorScheme
                                              .onSurfaceVariant,
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Crew Pulse Status',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (_myPulse != null)
                        TextButton(
                          onPressed: () => _clearPulse(activeTrip.id),
                          child: const Text('Clear Status'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_pulseCounts.isEmpty)
                    Text(
                      'No active pulses right now. Tap an option above to share your need.',
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
                          orElse: () => {
                            'emoji':
                                PulseType.fromString(entry.key)?.emoji ?? '📍',
                          },
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
                            '${opt['emoji']} ${entry.value} ${entry.key}',
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
