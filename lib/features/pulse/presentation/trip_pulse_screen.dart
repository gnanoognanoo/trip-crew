import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/core/services/analytics_service.dart';

/// Screen 15: Trip Pulse screen matching UI design mockup.
class TripPulseScreen extends ConsumerStatefulWidget {
  const TripPulseScreen({super.key});

  @override
  ConsumerState<TripPulseScreen> createState() => _TripPulseScreenState();
}

class _TripPulseScreenState extends ConsumerState<TripPulseScreen> {
  String? _selectedPulse = 'Hungry';

  final List<Map<String, dynamic>> _pulseOptions = const [
    {
      'title': 'Hungry',
      'icon': Icons.restaurant_rounded,
      'color': Color(0xFFF97316),
      'count': 4,
    },
    {
      'title': 'Need Coffee',
      'icon': Icons.local_cafe_rounded,
      'color': Color(0xFF3B82F6),
      'count': 1,
    },
    {
      'title': 'Need Fuel',
      'icon': Icons.local_gas_station_rounded,
      'color': Color(0xFF10B981),
      'count': 0,
    },
    {
      'title': 'Restroom',
      'icon': Icons.wc_rounded,
      'color': Color(0xFF06B6D4),
      'count': 0,
    },
    {
      'title': 'Tired',
      'icon': Icons.bed_rounded,
      'color': Color(0xFFD97706),
      'count': 1,
    },
    {
      'title': 'Want Photos',
      'icon': Icons.camera_alt_rounded,
      'color': Color(0xFF8B5CF6),
      'count': 2,
    },
    {
      'title': 'Need Break',
      'icon': Icons.pan_tool_rounded,
      'color': Color(0xFFE11D48),
      'count': 0,
    },
    {
      'title': 'Emergency',
      'icon': Icons.warning_amber_rounded,
      'color': Color(0xFFDC2626),
      'count': 0,
    },
  ];

  void _selectPulse(String title) {
    setState(() => _selectedPulse = title);
    AnalyticsService.logPulseSent('trip_goa_01', title);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Pulse updated: $title shared with crew!'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                    'Tap a pulse to share your real-time need with your crew.',
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
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spaceLg,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.4,
                ),
                itemCount: _pulseOptions.length,
                itemBuilder: (context, index) {
                  final opt = _pulseOptions[index];
                  final isSelected = _selectedPulse == opt['title'];
                  final Color color = opt['color'];

                  return InkWell(
                    onTap: () => _selectPulse(opt['title']),
                    borderRadius: BorderRadius.circular(AppConstants.radiusLg),
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
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(opt['icon'], color: color, size: 26),
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
                  );
                },
              ),
            ),

            // Bottom "Crew Pulse" Summary
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
                    'Crew Pulse',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildPulseStat('🍕 4 hungry'),
                      const SizedBox(width: 8),
                      _buildPulseStat('☕ 1 need coffee'),
                      const SizedBox(width: 8),
                      _buildPulseStat('🥱 1 tired'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPulseStat(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}
