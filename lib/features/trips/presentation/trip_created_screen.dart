import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tripcrew/app/theme.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/core/services/analytics_service.dart';
import 'package:tripcrew/core/widgets/tripcrew_motion.dart';
import 'package:tripcrew/features/trips/models/trip_model.dart';
import 'package:tripcrew/features/trips/services/trip_share_service.dart';

/// Screen 5: Professional, aesthetic, and live Trip Created confirmation screen.
class TripCreatedScreen extends StatefulWidget {
  final TripModel trip;

  const TripCreatedScreen({super.key, required this.trip});

  @override
  State<TripCreatedScreen> createState() => _TripCreatedScreenState();
}

class _TripCreatedScreenState extends State<TripCreatedScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dateFormat = DateFormat('dd MMM yyyy');

    final dateRangeText = widget.trip.endDate.isAfter(widget.trip.startDate)
        ? '${dateFormat.format(widget.trip.startDate)} – ${dateFormat.format(widget.trip.endDate)}'
        : dateFormat.format(widget.trip.startDate);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceLg),
          child: Column(
            children: [
              const SizedBox(height: AppConstants.spaceMd),

              // Architectural Stamp Emblem with Bobbing Accent
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.raisedSurface : const Color(0xFFEFEADB),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppTheme.trailCoral.withValues(alpha: 0.6),
                      width: 2.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.trailCoral.withValues(alpha: 0.15),
                        blurRadius: 18,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: BobbingSticker(
                      distance: 3,
                      duration: Duration(milliseconds: 2200),
                      child: Text('🧭', style: TextStyle(fontSize: 36)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spaceLg),

              // Title & Subtitle
              Text(
                'Trip Created!',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Your shared crew workspace is live and ready.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: AppConstants.spaceXl),

              // Immersive Live Trip Card
              Container(
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.raisedSurface : Colors.white,
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  border: Border.all(
                    color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
                    width: 1.0,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Bar with Live Indicator & Expedition Tag
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Live Pulsing Dot
                          Row(
                            children: [
                              AnimatedBuilder(
                                animation: _pulseAnimation,
                                builder: (context, child) {
                                  return Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: const Color(0xFF22C55E).withValues(
                                        alpha: _pulseAnimation.value,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF22C55E).withValues(
                                            alpha: _pulseAnimation.value * 0.6,
                                          ),
                                          blurRadius: 6,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'LIVE EXPEDITION',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2,
                                  color: Color(0xFF22C55E),
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF1F2533)
                                  : const Color(0xFFF1EFEA),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              widget.trip.tripType.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Divider(height: 1, thickness: 1),

                    // Main Content: Trip Name, Route & Schedule
                    Padding(
                      padding: const EdgeInsets.all(AppConstants.spaceLg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.trip.name,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Route visualization
                          Row(
                            children: [
                              // Starting place
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'FROM',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.0,
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      widget.trip.startingPlace.isNotEmpty
                                          ? widget.trip.startingPlace
                                          : 'Origin',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Route connector
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 10),
                                child: DottedRouteLine(
                                  color: AppTheme.pine,
                                  dotColor: AppTheme.sage,
                                  emoji: '✈️',
                                ),
                              ),

                              // Destination
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      'DESTINATION',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.0,
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      widget.trip.destination,
                                      textAlign: TextAlign.end,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Date bar
                          Row(
                            children: [
                              Icon(
                                Icons.calendar_today_rounded,
                                size: 14,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                dateRangeText,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppConstants.spaceLg),

              // Crew Access Section
              Text(
                'Invite your crew',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppConstants.spaceSm),

              // Code Box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.raisedSurface : Colors.white,
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  border: Border.all(
                    color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
                    width: 1.0,
                  ),
                ),
                child: Center(
                  child: Text(
                    widget.trip.inviteCode,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                      letterSpacing: 3.0,
                      color: isDark ? AppTheme.softSage : AppTheme.pine,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spaceMd),

              // Action buttons (Copy Code, Share)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: widget.trip.inviteCode));
                        AnalyticsService.logInviteShared(widget.trip.id);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Invite code copied to clipboard!'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('Copy Code'),
                    ),
                  ),
                  const SizedBox(width: AppConstants.spaceSm),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        TripShareService.shareTripInvite(
                          trip: widget.trip,
                          context: context,
                        );
                      },
                      icon: const Icon(Icons.share_rounded, size: 18),
                      label: const Text('Share'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppConstants.spaceSm),

              // Show QR Code & Share Option
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    TripShareService.showQrModal(
                      context,
                      inviteCode: widget.trip.inviteCode,
                      tripName: widget.trip.name,
                      tripId: widget.trip.id,
                      startingPlace: widget.trip.startingPlace,
                      destination: widget.trip.destination,
                      startDate: widget.trip.startDate,
                      endDate: widget.trip.endDate,
                    );
                  },
                  icon: const Icon(Icons.qr_code_2_rounded, size: 20),
                  label: const Text('Show QR Code & Share'),
                ),
              ),
              const SizedBox(height: AppConstants.spaceMd),

              Text(
                'Invite your friends and start planning together!',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppConstants.spaceXl),

              // Done Button
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => context.go('/workspace'),
                  child: const Text('Done'),
                ),
              ),
              const SizedBox(height: AppConstants.spaceLg),
            ],
          ),
        ),
      ),
    );
  }
}
