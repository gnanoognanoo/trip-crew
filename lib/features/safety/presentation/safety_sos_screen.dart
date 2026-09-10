import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tripcrew/core/constants/app_constants.dart';

/// Screen 17: Safety / SOS screen matching UI design mockup.
class SafetySosScreen extends ConsumerStatefulWidget {
  const SafetySosScreen({super.key});

  @override
  ConsumerState<SafetySosScreen> createState() => _SafetySosScreenState();
}

class _SafetySosScreenState extends ConsumerState<SafetySosScreen> {
  bool _sosSent = false;

  void _triggerSos() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Emergency SOS Alert? 🚨'),
        content: const Text(
          'This will immediately alert all 4 crew members with your live GPS location and continuous audio beacon.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _sosSent = true);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  backgroundColor: Color(0xFFDC2626),
                  content: Text('EMERGENCY SOS BROADCASTED TO CREW!'),
                ),
              );
            },
            child: const Text('Broadcast SOS'),
          ),
        ],
      ),
    );
  }

  void _sendImSafe() {
    setState(() => _sosSent = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFF10B981),
        content: Text("Marked as Safe: Crew notified that you're okay!"),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Safety / SOS'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceLg),
          child: Column(
            children: [
              const SizedBox(height: AppConstants.spaceLg),

              // SOS Circular Pulse Button
              Center(
                child: Column(
                  children: [
                    InkWell(
                      onTap: _triggerSos,
                      borderRadius: BorderRadius.circular(90),
                      child: Container(
                        width: 170,
                        height: 170,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFFEE2E2),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFFDC2626,
                              ).withValues(alpha: 0.25),
                              blurRadius: 24,
                              spreadRadius: 8,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Container(
                            width: 130,
                            height: 130,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFFDC2626),
                            ),
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.warning_rounded,
                                  color: Colors.white,
                                  size: 36,
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'SEND SOS',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppConstants.spaceMd),
                    Text(
                      _sosSent
                          ? '🚨 SOS ACTIVE - CREW ALERTED'
                          : 'Alert your crew and share your location',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _sosSent
                            ? const Color(0xFFDC2626)
                            : theme.colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppConstants.spaceXl),

              // Emergency Information List
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.red.shade50,
                        child: const Icon(
                          Icons.local_hospital_rounded,
                          color: Colors.red,
                          size: 22,
                        ),
                      ),
                      title: const Text(
                        'Nearby Hospitals',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text(
                        'Manipal Hospital Goa (3.4 km)',
                        style: TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Hospital list & emergency dialer'),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue.shade50,
                        child: const Icon(
                          Icons.local_police_rounded,
                          color: Colors.blue,
                          size: 22,
                        ),
                      ),
                      title: const Text(
                        'Police Station',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text(
                        'Calangute Police (1.8 km)',
                        style: TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Police station contact info'),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.green.shade50,
                        child: const Icon(
                          Icons.contact_phone_rounded,
                          color: Colors.green,
                          size: 22,
                        ),
                      ),
                      title: const Text(
                        'Emergency Contacts',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text(
                        'Family & Embassy Hotline',
                        style: TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Emergency contacts list'),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),

              const Spacer(),

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
                    "Let everyone know you've reached safely",
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
              const SizedBox(height: AppConstants.spaceLg),
            ],
          ),
        ),
      ),
    );
  }
}
