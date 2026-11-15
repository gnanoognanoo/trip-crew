import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/core/services/supabase_service.dart';
import 'package:tripcrew/features/auth/providers/auth_provider.dart';
import 'package:tripcrew/features/trips/providers/trips_provider.dart';

class SafetySosScreen extends ConsumerStatefulWidget {
  const SafetySosScreen({super.key});

  @override
  ConsumerState<SafetySosScreen> createState() => _SafetySosScreenState();
}

class _SafetySosScreenState extends ConsumerState<SafetySosScreen>
    with SingleTickerProviderStateMixin {
  bool _sosActive = false;
  Position? _currentPosition;
  String? _locationStatus;
  Timer? _countdownTimer;
  int _countdownSeconds = 5;
  late AnimationController _pulseAnimCtrl;

  @override
  void initState() {
    super.initState();
    _pulseAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _checkLocation();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pulseAnimCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _locationStatus = 'Location services are disabled on this device.');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => _locationStatus = 'Location permission is denied. GPS link will not be included.');
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );

      if (mounted) {
        setState(() {
          _currentPosition = pos;
          _locationStatus = null;
        });
      }
    } catch (e) {
      developer.log('Location check error: $e', name: 'SafetySos');
      if (mounted) {
        setState(() => _locationStatus = 'Could not acquire GPS position.');
      }
    }
  }

  void _initiateSosCountdown() {
    setState(() => _countdownSeconds = 5);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          _countdownTimer?.cancel();
          _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
            if (_countdownSeconds <= 1) {
              timer.cancel();
              Navigator.pop(ctx);
              _broadcastSos();
            } else {
              setDialogState(() {
                _countdownSeconds--;
              });
            }
          });

          return AlertDialog(
            icon: const Icon(Icons.warning_amber_rounded, size: 48, color: Colors.red),
            title: const Text('Emergency SOS Triggered!'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Broadcasting emergency alert in $_countdownSeconds seconds...',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 12),
                const Text(
                  'This will prepare your GPS location and emergency message for instant sharing with crew & emergency contacts.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.black87),
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: _countdownSeconds / 5.0,
                  color: Colors.red,
                  backgroundColor: Colors.red.shade100,
                ),
              ],
            ),
            actions: [
              OutlinedButton(
                onPressed: () {
                  _countdownTimer?.cancel();
                  Navigator.pop(ctx);
                },
                child: const Text('Cancel / Abort'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () {
                  _countdownTimer?.cancel();
                  Navigator.pop(ctx);
                  _broadcastSos();
                },
                child: const Text('Send Now'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _broadcastSos() async {
    final activeTrip = ref.read(activeTripProvider);
    final user = ref.read(authProvider).user;

    // Refresh location if possible
    await _checkLocation();

    final userName = user?.name.isNotEmpty == true ? user!.name : 'Crew Member';
    final tripName = activeTrip?.name ?? 'Trip';

    String locationSnippet = '';
    if (_currentPosition != null) {
      final lat = _currentPosition!.latitude;
      final lon = _currentPosition!.longitude;
      locationSnippet = '''
📍 Current GPS Location:
Latitude: $lat
Longitude: $lon
Google Maps Link: https://maps.google.com/?q=$lat,$lon
''';
    } else {
      locationSnippet = '📍 GPS Location: Unavailable (Permission denied or signal weak)\n';
    }

    final message = '''
🚨 EMERGENCY SOS ALERT!
From: $userName
Trip: $tripName
Time: ${DateTime.now().toLocal()}

$locationSnippet
I need immediate assistance! Please check on me or coordinate help.
''';

    // 1. Broadcast to Supabase trip_pulses if online
    if (SupabaseService.isInitialized && activeTrip != null) {
      try {
        final pulseId = 'sos_${DateTime.now().millisecondsSinceEpoch}';
        await SupabaseService.client.from('trip_pulses').insert({
          'id': pulseId,
          'trip_id': activeTrip.id,
          'user_id': user?.uid ?? 'unknown',
          'user_name': userName,
          'pulse_type': 'emergency_sos',
          'type': 'SOS',
          'message': message,
          'latitude': _currentPosition?.latitude,
          'longitude': _currentPosition?.longitude,
          'is_active': true,
          'created_at': DateTime.now().toIso8601String(),
          'expires_at': DateTime.now().add(const Duration(hours: 6)).toIso8601String(),
        });
      } catch (e) {
        developer.log('Failed saving SOS pulse to Supabase: $e', name: 'SafetySos');
      }
    }

    setState(() => _sosActive = true);

    // 2. Open native device share sheet to send to contacts / WhatsApp / SMS
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: message,
          subject: 'EMERGENCY SOS: $userName needs help!',
        ),
      );
    } catch (e) {
      developer.log('Device share error: $e', name: 'SafetySos');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open device share sheet: $e')),
        );
      }
    }
  }

  Future<void> _sendImSafe() async {
    final activeTrip = ref.read(activeTripProvider);
    final user = ref.read(authProvider).user;

    if (SupabaseService.isInitialized && activeTrip != null && user != null) {
      try {
        // Mark active SOS pulses as resolved
        await SupabaseService.client
            .from('trip_pulses')
            .update({'is_active': false})
            .eq('trip_id', activeTrip.id)
            .eq('user_id', user.uid)
            .eq('pulse_type', 'emergency_sos');
      } catch (e) {
        developer.log('Error marking safe: $e', name: 'SafetySos');
      }
    }

    setState(() => _sosActive = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF10B981),
          content: Text("Marked as Safe: Emergency status cleared!"),
        ),
      );
    }
  }

  Future<void> _callEmergencyNumber(String number, String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Call $label ($number)?'),
        content: Text('This will open your phone dialer to call $number.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Open Dialer'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final uri = Uri.parse('tel:$number');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not launch dialer for $number')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Dialer error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Safety & Emergency SOS'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () { if (context.canPop()) { context.pop(); } else { context.go('/workspace'); } },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceLg),
          child: Column(
            children: [
              const SizedBox(height: AppConstants.spaceLg),

              // SOS Circular Pulse Button
              Center(
                child: Column(
                  children: [
                    AnimatedBuilder(
                      animation: _pulseAnimCtrl,
                      builder: (context, child) {
                        return Container(
                          width: 170 + (_sosActive ? _pulseAnimCtrl.value * 20 : 0),
                          height: 170 + (_sosActive ? _pulseAnimCtrl.value * 20 : 0),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFFEE2E2),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFDC2626).withValues(
                                  alpha: _sosActive ? 0.4 : 0.2,
                                ),
                                blurRadius: _sosActive ? 32 : 20,
                                spreadRadius: _sosActive ? 8 : 4,
                              ),
                            ],
                          ),
                          child: Center(
                            child: InkWell(
                              onTap: _initiateSosCountdown,
                              borderRadius: BorderRadius.circular(90),
                              child: Container(
                                width: 130,
                                height: 130,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _sosActive
                                      ? const Color(0xFFB91C1C)
                                      : const Color(0xFFDC2626),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.warning_rounded,
                                      color: Colors.white,
                                      size: 38,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _sosActive ? 'SOS ACTIVE' : 'SEND SOS',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15,
                                        letterSpacing: 1.0,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: AppConstants.spaceMd),
                    Text(
                      _sosActive
                          ? '🚨 SOS ACTIVE • CREW & CONTACTS ALERTED'
                          : 'Tap to broadcast emergency location to crew & contacts',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _sosActive
                            ? const Color(0xFFDC2626)
                            : theme.colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppConstants.spaceMd),

              // Location Status Card
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _currentPosition != null
                      ? const Color(0xFFF0FDF4)
                      : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _currentPosition != null
                        ? const Color(0xFFBBF7D0)
                        : const Color(0xFFF59E0B),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _currentPosition != null
                          ? Icons.gps_fixed_rounded
                          : Icons.gps_not_fixed_rounded,
                      size: 20,
                      color: _currentPosition != null
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFD97706),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _currentPosition != null
                            ? 'GPS Ready: ${_currentPosition!.latitude.toStringAsFixed(4)}, ${_currentPosition!.longitude.toStringAsFixed(4)}'
                            : (_locationStatus ?? 'Checking GPS position...'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _currentPosition != null
                              ? const Color(0xFF15803D)
                              : const Color(0xFF92400E),
                        ),
                      ),
                    ),
                    if (_currentPosition == null)
                      TextButton(
                        onPressed: _checkLocation,
                        child: const Text('Retry', style: TextStyle(fontSize: 12)),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: AppConstants.spaceLg),

              // Emergency Helplines (Actual Phone Dialer triggers)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Emergency Helplines (Tap to Call)',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spaceSm),

              Card(
                elevation: 1.5,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.red.shade50,
                        child: const Icon(
                          Icons.emergency_rounded,
                          color: Colors.red,
                          size: 22,
                        ),
                      ),
                      title: const Text(
                        'National Emergency (112)',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text(
                        'Police, Fire & Medical Universal Hotline • Tap to dial',
                        style: TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.call_rounded, color: Colors.red),
                      onTap: () => _callEmergencyNumber('112', 'National Emergency'),
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue.shade50,
                        child: const Icon(
                          Icons.local_hospital_rounded,
                          color: Colors.blue,
                          size: 22,
                        ),
                      ),
                      title: const Text(
                        'Ambulance & Medical (108)',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text(
                        'Direct Emergency Medical Ambulance • Tap to dial',
                        style: TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.call_rounded, color: Colors.blue),
                      onTap: () => _callEmergencyNumber('108', 'Medical Ambulance'),
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.green.shade50,
                        child: const Icon(
                          Icons.local_police_rounded,
                          color: Colors.green,
                          size: 22,
                        ),
                      ),
                      title: const Text(
                        'Police Assistance (100)',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text(
                        'Police Helpline • Tap to dial',
                        style: TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.call_rounded, color: Colors.green),
                      onTap: () => _callEmergencyNumber('100', 'Police Assistance'),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppConstants.spaceLg),

              // "I'm Safe" Confirmation Card
              Card(
                color: const Color(0xFFF0FDF4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                  side: const BorderSide(color: Color(0xFFBBF7D0)),
                ),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF10B981),
                    child: Icon(Icons.check, color: Colors.white),
                  ),
                  title: const Text(
                    "I'm Safe",
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF15803D),
                    ),
                  ),
                  subtitle: const Text(
                    "Notify crew that you're okay and clear emergency status",
                    style: TextStyle(fontSize: 12, color: Color(0xFF166534)),
                  ),
                  trailing: FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _sendImSafe,
                    child: const Text('Confirm'),
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spaceXl),
            ],
          ),
        ),
      ),
    );
  }
}
