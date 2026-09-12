import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/core/services/live_crew_service.dart';
import 'package:tripcrew/core/widgets/app_error_state.dart';
import 'package:tripcrew/features/maps/models/live_location_model.dart';
import 'package:tripcrew/features/maps/presentation/widgets/crew_radar_painter.dart';
import 'package:tripcrew/features/maps/providers/live_crew_provider.dart';
import 'package:tripcrew/features/maps/utils/location_calculator.dart';
import 'package:tripcrew/features/pulse/models/trip_pulse.dart';
import 'package:tripcrew/features/trips/providers/trips_provider.dart';

/// Screen 14: Production Live Crew Location system featuring interactive Crew Radar,
/// proximity alerts, and battery-safe background sharing without Google Maps.
class LiveCrewLocationScreen extends ConsumerStatefulWidget {
  const LiveCrewLocationScreen({super.key});

  @override
  ConsumerState<LiveCrewLocationScreen> createState() =>
      _LiveCrewLocationScreenState();
}

class _LiveCrewLocationScreenState extends ConsumerState<LiveCrewLocationScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  String? _selectedMemberUid;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _showPrivacyInfo() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: Color(0xFF10B981)),
            SizedBox(width: 8),
            Text('Live Crew Privacy'),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '• Opt-In Only: Live sharing defaults to OFF. TripCrew never silently tracks your GPS.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              SizedBox(height: 8),
              Text(
                '• Firestore Security: Only authenticated members of your active trip can view your live coordinates.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              SizedBox(height: 8),
              Text(
                '• Spark Cost & Battery Throttling: Location writes are throttled to every 15–30 seconds while moving, and reduce to heartbeats when stationary.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              SizedBox(height: 8),
              Text(
                '• Hard Expiry: Every active sharing session contains an explicit expiry timestamp. If expired, coordinates are treated as off and cleaned up whenever the app runs.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Future<bool> _showForegroundExplanationDialog(String tripName) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.share_location_rounded,
          color: Color(0xFF10B981),
          size: 36,
        ),
        title: const Text('Live Crew Location', textAlign: TextAlign.center),
        content: Text(
          'TripCrew uses your location to calculate real-time proximity and bearing with your crew in $tripName so you can easily regroup.\n\n'
          '• Only authenticated members of this trip can see your distance\n'
          '• Sharing is strictly opt-in and stops automatically\n'
          '• No silent background tracking without your permission',
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not Now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<bool> _showBackgroundDisclosureDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.screen_lock_portrait_rounded,
          color: Color(0xFF10B981),
          size: 36,
        ),
        title: const Text(
          'Background Location Access',
          textAlign: TextAlign.center,
        ),
        content: const Text(
          'TripCrew uses your location to keep your selected trip crew updated even when the app is minimized or your screen is locked. Sharing starts only when you enable Live Crew and stops when you turn it off or the selected sharing period ends.\n\n'
          'You can allow background sharing or keep sharing only while the app is actively on screen.',
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Foreground Only'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
            ),
            child: const Text('Allow Background Sharing'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _showEnableGpsDialog() async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.location_off_rounded,
          color: Colors.amber,
          size: 36,
        ),
        title: const Text('Location Services Disabled'),
        content: const Text(
          'Please turn on your device GPS to enable Live Crew sharing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Geolocator.openLocationSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPermissionSettingsDialog() async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.block_rounded, color: Colors.red, size: 36),
        title: const Text('Location Permission Blocked'),
        content: const Text(
          'Location access is permanently disabled for TripCrew. Please enable location permissions in App Settings to share your position.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Geolocator.openAppSettings();
            },
            child: const Text('App Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleStartSharing({
    required String mode,
    required DateTime until,
  }) async {
    final activeTrip = ref.read(activeTripProvider);
    if (activeTrip == null) return;

    // 1. Check GPS hardware state
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      await _showEnableGpsDialog();
      return;
    }

    // 2. Check current foreground permission
    var permission = await Geolocator.checkPermission();

    // Progressive step A: Show TripCrew explanation before requesting foreground location
    if (permission == LocationPermission.denied) {
      if (!mounted) return;
      final proceed = await _showForegroundExplanationDialog(activeTrip.name);
      if (!proceed) return;

      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Location permission is required to share your live location.',
          ),
        ),
      );
      return;
    }

    if (permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      await _showPermissionSettingsDialog();
      return;
    }

    // Progressive step B: Start foreground sharing (user-initiated while TripCrew is open)
    await ref
        .read(liveCrewProvider.notifier)
        .startSharing(mode: mode, until: until);

    // Progressive step C: If foreground permission granted (whileInUse), explain background location
    // and guide/request background location separately according to Android 11+ requirements.
    if (permission == LocationPermission.whileInUse) {
      if (!mounted) return;
      final wantsBackground = await _showBackgroundDisclosureDialog();
      if (wantsBackground == true) {
        final bgPermission = await Geolocator.requestPermission();
        if (bgPermission == LocationPermission.always && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Background location enabled for continuous crew updates.',
              ),
              backgroundColor: Color(0xFF10B981),
            ),
          );
        }
      }
      // If user refuses background access (Foreground Only), sharing remains ACTIVE in foreground mode.
    }
  }

  void _showStartSharingSheet() {
    final activeTrip = ref.read(activeTripProvider);
    if (activeTrip == null) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final now = DateTime.now();
        final oneHour = now.add(const Duration(hours: 1));
        final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);
        // Requirement 7: For "Until Trip Ends", always resolve the trip's end date/time into sharingUntil
        final tripEnd = DateTime(
          activeTrip.endDate.year,
          activeTrip.endDate.month,
          activeTrip.endDate.day,
          23,
          59,
          59,
        );
        final isTripActive = tripEnd.isAfter(now);

        final timeFormat = DateFormat('h:mm a');
        final dateFormat = DateFormat('dd MMM');

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spaceLg,
              vertical: AppConstants.spaceMd,
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
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: AppConstants.spaceMd),
                Text(
                  'Share Live Location',
                  style: Theme.of(
                    ctx,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Select how long your crew in ${activeTrip.name} can see your position.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
                const SizedBox(height: AppConstants.spaceLg),
                _buildSharingOption(
                  icon: Icons.timer_outlined,
                  title: 'Share for 1 Hour',
                  subtitle:
                      'Ideal for quick stops & regrouping (until ${timeFormat.format(oneHour)})',
                  onTap: () {
                    Navigator.pop(ctx);
                    _handleStartSharing(mode: '1_hour', until: oneHour);
                  },
                ),
                _buildSharingOption(
                  icon: Icons.wb_sunny_outlined,
                  title: 'Share Until End of Day',
                  subtitle: 'Active until 11:59 PM tonight',
                  onTap: () {
                    Navigator.pop(ctx);
                    _handleStartSharing(
                      mode: 'until_end_of_day',
                      until: endOfDay,
                    );
                  },
                ),
                if (isTripActive)
                  _buildSharingOption(
                    icon: Icons.luggage_outlined,
                    title: 'Share Until Trip Ends',
                    subtitle: 'Active through ${dateFormat.format(tripEnd)}',
                    onTap: () {
                      Navigator.pop(ctx);
                      _handleStartSharing(
                        mode: 'until_trip_ends',
                        until: tripEnd,
                      );
                    },
                  ),
                const SizedBox(height: AppConstants.spaceSm),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSharingOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppConstants.spaceSm),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.15),
          child: Icon(icon, color: const Color(0xFF10B981), size: 20),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeTrip = ref.watch(activeTripProvider);
    final crewState = ref.watch(liveCrewProvider);

    if (activeTrip == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Live Crew Location')),
        body: const Center(child: Text('No active trip selected.')),
      );
    }

    if (crewState.errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Live Crew Location')),
        body: AppErrorState(
          title: 'Location Sync Error',
          message: crewState.errorMessage!,
          onRetry: () => ref.invalidate(liveCrewProvider),
        ),
      );
    }

    final activeDistances = crewState.distances;
    final groupStatus = crewState.groupStatus;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Crew Location'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.shield_outlined),
            tooltip: 'Privacy Info',
            onPressed: _showPrivacyInfo,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceLg),
          children: [
            const SizedBox(height: AppConstants.spaceSm),

            // Emergency Alert Banners (if any member sent Emergency Pulse)
            if (crewState.emergencyMembers.isNotEmpty) ...[
              _buildEmergencyBanners(
                theme,
                crewState.emergencyMembers,
                activeDistances,
              ),
              const SizedBox(height: AppConstants.spaceSm),
            ],

            // 1. Group Proximity Status Banner & Insights
            _buildGroupStatusBanner(
              theme,
              groupStatus,
              crewState.combinedInsights,
            ),
            const SizedBox(height: AppConstants.spaceMd),

            // 2. Permission / Service Alert if not ready
            if (crewState.serviceState ==
                LocationServiceState.serviceDisabled) ...[
              _buildAlertBanner(
                theme,
                color: Colors.amber,
                icon: Icons.location_off_rounded,
                title: 'Location Services Disabled',
                subtitle:
                    'Turn on device GPS to broadcast and see crew distances.',
                actionLabel: 'Open Settings',
                onAction: () =>
                    ref.read(liveCrewProvider.notifier).openSettings(),
              ),
              const SizedBox(height: AppConstants.spaceMd),
            ] else if (crewState.serviceState ==
                LocationServiceState.permissionDeniedForever) ...[
              _buildAlertBanner(
                theme,
                color: Colors.red,
                icon: Icons.block_rounded,
                title: 'Location Permission Blocked',
                subtitle:
                    'Please enable location in App Settings to use Live Crew.',
                actionLabel: 'App Settings',
                onAction: () =>
                    ref.read(liveCrewProvider.notifier).openSettings(),
              ),
              const SizedBox(height: AppConstants.spaceMd),
            ],

            // 3. Tactical "Crew Radar" Visualization
            _buildRadarCard(theme, crewState),
            const SizedBox(height: AppConstants.spaceLg),

            // 4. Compact Crew Pulse Status Summary
            _buildCrewPulseSummary(theme, crewState.crewPulseCounts),

            // 5. Current User Sharing Control Panel
            _buildCurrentUserPanel(theme, crewState),
            const SizedBox(height: AppConstants.spaceLg),

            // 5. Crew Member Cards Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Crew Members (${crewState.members.length})',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Threshold: ${kTogetherThresholdMeters.round()}m',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spaceSm),

            if (crewState.members.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppConstants.spaceLg),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.radar_outlined,
                          size: 36,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'No crew members sharing location yet',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'When friends join ${activeTrip.name} and tap "Start Sharing", they will appear on your radar.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              ...crewState.members.map((member) {
                final dist = activeDistances[member.uid];
                final isSelected = member.uid == _selectedMemberUid;
                return _buildMemberCard(theme, member, dist, isSelected);
              }),

            const SizedBox(height: AppConstants.space2xl),
          ],
        ),
      ),
    );
  }

  Widget _buildEmergencyBanners(
    ThemeData theme,
    List<LiveLocationModel> emergencyMembers,
    Map<String, double> distances,
  ) {
    return Column(
      children: emergencyMembers.map((m) {
        final d = distances[m.uid];
        final locationText =
            (m.isSharing && !m.isExpired && m.hasCoordinates && d != null)
            ? LocationCalculator.formatDistance(d)
            : 'Location unavailable';

        return Container(
          margin: const EdgeInsets.only(bottom: AppConstants.spaceSm),
          padding: const EdgeInsets.all(AppConstants.spaceMd),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            border: Border.all(color: const Color(0xFFDC2626), width: 2),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFFDC2626),
                  shape: BoxShape.circle,
                ),
                child: const Text('🚨', style: TextStyle(fontSize: 20)),
              ),
              const SizedBox(width: AppConstants.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${m.displayName} needs attention',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF991B1B),
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      locationText,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFDC2626),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'In-app alert only (no emergency services contacted)',
                      style: TextStyle(fontSize: 11, color: Color(0xFF7F1D1D)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildGroupStatusBanner(
    ThemeData theme,
    GroupStatus status,
    List<String> insights,
  ) {
    final Color bgColor = status.isTogether
        ? const Color(0xFF10B981).withValues(alpha: 0.15)
        : const Color(0xFFF59E0B).withValues(alpha: 0.15);
    final Color textColor = status.isTogether
        ? const Color(0xFF065F46)
        : const Color(0xFF92400E);
    final Color iconColor = status.isTogether
        ? const Color(0xFF10B981)
        : const Color(0xFFF59E0B);

    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceMd),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: iconColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                status.isTogether
                    ? Icons.check_circle_rounded
                    : Icons.warning_amber_rounded,
                color: iconColor,
                size: 26,
              ),
              const SizedBox(width: AppConstants.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status.statusTitle,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: textColor,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      status.statusSubtitle,
                      style: TextStyle(
                        color: textColor.withValues(alpha: 0.8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (insights.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: insights.map((insight) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Icon(
                          Icons.insights_rounded,
                          size: 14,
                          color: textColor,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            insight,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: textColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCrewPulseSummary(ThemeData theme, Map<String, int> pulseCounts) {
    if (pulseCounts.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: AppConstants.spaceLg),
      padding: const EdgeInsets.all(AppConstants.spaceMd),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'CREW PULSE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                  color: theme.colorScheme.primary,
                ),
              ),
              InkWell(
                onTap: () => context.push('/pulse'),
                child: Text(
                  'Open Pulse',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceSm),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: pulseCounts.entries.map((e) {
              final pEnum = PulseType.fromString(e.key);
              final emoji = pEnum?.emoji ?? '📍';
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Text(
                  '$emoji ${e.value} ${e.key}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertBanner(
    ThemeData theme, {
    required Color color,
    required IconData icon,
    required String title,
    required String subtitle,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceMd),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: AppConstants.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 11, color: Colors.black87),
                ),
              ],
            ),
          ),
          FilledButton.tonal(
            onPressed: onAction,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            ),
            child: Text(actionLabel, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildRadarCard(ThemeData theme, LiveCrewState state) {
    return Card(
      elevation: 3,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        color: const Color(0xFF0B132B),
        padding: const EdgeInsets.all(AppConstants.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.radar_rounded,
                      color: Color(0xFF10B981),
                      size: 18,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Crew Radar',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
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
                    color: const Color(0xFF10B981).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'TACTICAL PROXIMITY',
                    style: TextStyle(
                      color: Color(0xFF10B981),
                      fontWeight: FontWeight.w800,
                      fontSize: 9,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            const Text(
              'Relative proximity & bearing • Not a geographic street map',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
            const SizedBox(height: AppConstants.spaceSm),

            // Animated Canvas Radar
            Center(
              child: AnimatedBuilder(
                animation: _animCtrl,
                builder: (context, child) {
                  return SizedBox(
                    width: 280,
                    height: 280,
                    child: CustomPaint(
                      painter: CrewRadarPainter(
                        members: state.members,
                        distances: state.distances,
                        bearings: state.bearings,
                        selectedMemberUid: _selectedMemberUid,
                        animationValue: _animCtrl.value,
                        isUserSharing: state.isSharing,
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: AppConstants.spaceSm),
            // Radar Legend
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendItem(const Color(0xFF38BDF8), 'You'),
                const SizedBox(width: 14),
                _buildLegendItem(const Color(0xFF10B981), 'Together (≤250m)'),
                const SizedBox(width: 14),
                _buildLegendItem(const Color(0xFFF59E0B), 'Away (>250m)'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildCurrentUserPanel(ThemeData theme, LiveCrewState state) {
    final timeFormat = DateFormat('h:mm a');
    final isSharing = state.isSharing;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: isSharing
                            ? const Color(0xFF10B981)
                            : Colors.grey.shade400,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'YOUR LOCATION',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isSharing
                        ? const Color(0xFF10B981).withValues(alpha: 0.15)
                        : Colors.grey.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    isSharing ? 'SHARING ACTIVE' : 'SHARING OFF',
                    style: TextStyle(
                      color: isSharing
                          ? const Color(0xFF065F46)
                          : Colors.grey.shade700,
                      fontWeight: FontWeight.w800,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (isSharing) ...[
              Text(
                'Your live location is being shared with this trip.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.schedule, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    state.sharingUntil != null
                        ? 'Sharing until ${timeFormat.format(state.sharingUntil!)}'
                        : 'Sharing active',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  if (LiveCrewService.instance.lastPosition != null) ...[
                    const SizedBox(width: 12),
                    Icon(
                      Icons.gps_fixed,
                      size: 14,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Acc: ${LiveCrewService.instance.lastPosition!.accuracy.round()}m',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () =>
                    ref.read(liveCrewProvider.notifier).stopSharing(),
                icon: const Icon(Icons.stop_circle_outlined, color: Colors.red),
                label: const Text(
                  'Stop Sharing',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  minimumSize: const Size.fromHeight(40),
                ),
              ),
            ] else ...[
              Text(
                'Live sharing is off.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Turn on sharing so friends can see your proximity and regroup easily.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _showStartSharingSheet,
                icon: const Icon(Icons.share_location_rounded, size: 18),
                label: const Text('Start Sharing'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(40),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMemberCard(
    ThemeData theme,
    LiveLocationModel member,
    double? distance,
    bool isSelected,
  ) {
    final isAway = distance != null && distance > kTogetherThresholdMeters;
    final isSharing =
        member.isSharing && !member.isExpired && member.hasCoordinates;
    final isStale = member.freshness == LocationFreshness.stale;
    final isEmergency = member.activePulse?.isEmergency == true;

    final String locationSubtitle;
    if (isSharing && distance != null) {
      locationSubtitle =
          '${LocationCalculator.formatDistance(distance)} • ${isStale ? "Stale" : "Live"}';
    } else if (member.isExpired) {
      locationSubtitle = 'Location unavailable';
    } else {
      locationSubtitle = 'Location sharing off';
    }

    final pulseLabel = member.effectivePulseLabel;

    return Card(
      margin: const EdgeInsets.only(bottom: AppConstants.spaceSm),
      elevation: isSelected ? 2 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isEmergency
            ? const BorderSide(color: Color(0xFFDC2626), width: 2)
            : (isSelected
                  ? const BorderSide(color: Color(0xFF10B981), width: 2)
                  : BorderSide.none),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          setState(() {
            _selectedMemberUid = isSelected ? null : member.uid;
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spaceMd),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 22,
                backgroundColor: isEmergency
                    ? const Color(0xFFFEE2E2)
                    : (isSharing
                          ? (isStale
                                ? Colors.grey.shade200
                                : (isAway
                                      ? const Color(
                                          0xFFF59E0B,
                                        ).withValues(alpha: 0.2)
                                      : const Color(
                                          0xFF10B981,
                                        ).withValues(alpha: 0.2)))
                          : Colors.grey.shade200),
                child: Text(
                  member.displayName.isNotEmpty
                      ? member.displayName[0].toUpperCase()
                      : 'M',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: isEmergency
                        ? const Color(0xFFDC2626)
                        : (isSharing
                              ? (isStale
                                    ? Colors.grey.shade600
                                    : (isAway
                                          ? const Color(0xFFD97706)
                                          : const Color(0xFF059669)))
                              : Colors.grey),
                  ),
                ),
              ),
              const SizedBox(width: AppConstants.spaceMd),

              // Name & Status
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      locationSubtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: isEmergency
                            ? const Color(0xFFDC2626)
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight: isEmergency
                            ? FontWeight.w700
                            : FontWeight.normal,
                      ),
                    ),
                    if (pulseLabel != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isEmergency
                              ? const Color(0xFFFEE2E2)
                              : const Color(0xFF10B981).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isEmergency
                                ? const Color(0xFFDC2626).withValues(alpha: 0.4)
                                : const Color(
                                    0xFF10B981,
                                  ).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          pulseLabel,
                          style: TextStyle(
                            color: isEmergency
                                ? const Color(0xFFDC2626)
                                : const Color(0xFF065F46),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Distance Badge
              if (isSharing && distance != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isStale
                            ? Colors.grey.shade200
                            : (isAway
                                  ? const Color(0xFFFEF3C7)
                                  : const Color(0xFFD1FAE5)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isStale
                            ? '${LocationCalculator.formatDistance(distance)} (Stale)'
                            : (isAway
                                  ? '${LocationCalculator.formatDistance(distance)} ⚠️'
                                  : LocationCalculator.formatDistance(
                                      distance,
                                    )),
                        style: TextStyle(
                          color: isStale
                              ? Colors.grey.shade700
                              : (isAway
                                    ? const Color(0xFFB45309)
                                    : const Color(0xFF047857)),
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                )
              else
                Text(
                  member.isExpired ? 'Unavailable' : 'Off',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade500,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
