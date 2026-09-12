import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/core/services/cloudinary_service.dart';
import 'package:tripcrew/features/auth/providers/auth_provider.dart';
import 'package:tripcrew/features/shared/presentation/beta_feedback_sheet.dart';
import 'package:tripcrew/features/trips/providers/trips_provider.dart';

/// Screen 19: Profile screen matching UI design mockup with Cloudinary avatar upload.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _changeAvatar(BuildContext context, WidgetRef ref) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );
      if (picked == null) return;

      final user = ref.read(authProvider).user;
      if (user == null || user.uid.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You must be signed in to update your avatar.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 12),
                Text('Uploading avatar to Cloudinary...'),
              ],
            ),
            duration: Duration(seconds: 4),
          ),
        );
      }

      final bytes = await picked.readAsBytes();
      final uploadRes = await CloudinaryService.uploadAvatar(
        bytes: bytes,
        filename: picked.name,
        uid: user.uid,
      );

      await ref
          .read(authProvider.notifier)
          .updateProfilePhoto(uploadRes.secureUrl);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Avatar updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload avatar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showPrivacyDialog(BuildContext context, String? userEmail) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: Colors.blue),
            SizedBox(width: 8),
            Text('Privacy & Media'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Media Delivery (Cloudinary Free Tier)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 4),
              const Text(
                '• Trip photos and avatars are shared with your crew inside TripCrew.\n'
                '• During this MVP beta, uploaded media is delivered via public-by-link CDN URLs.\n'
                '• Anyone who obtains the direct media URL may technically access that file.\n'
                '• True private media delivery with time-limited signed access is planned for future backend upgrades.',
                style: TextStyle(fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 12),
              const Text(
                'Live Location Sharing',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 4),
              const Text(
                '• Your GPS coordinates are ONLY broadcast to trip crew members when you explicitly turn on the "Live Crew Beacon" switch on the Map screen.\n'
                '• When the beacon is OFF, zero background location data is broadcast.',
                style: TextStyle(fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 12),
              const Text(
                'Account Data & Firestore',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                '• Signed in as: ${userEmail ?? 'Authenticated Traveler'}\n'
                '• Trip data and itineraries are protected via Google Cloud Firestore security rules with granular membership authorization.',
                style: const TextStyle(fontSize: 12, height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Understood'),
          ),
        ],
      ),
    );
  }

  void _showMyTripPaymentsModal(BuildContext context, WidgetRef ref) {
    final trips = ref.read(tripsProvider).trips;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spaceLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.savings_rounded,
                      color: Color(0xFF10B981),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'My Trip Payments',
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'TripCrew Pay is trip-specific. Select a trip below to view its shared Trip Pot, contribution history, and payment ledger.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: AppConstants.spaceMd),
              if (trips.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No trips found. Create or join a trip to access TripCrew Pay.',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: trips.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final trip = trips[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: const Color(
                            0xFF0F4C81,
                          ).withValues(alpha: 0.1),
                          child: const Icon(
                            Icons.luggage_rounded,
                            color: Color(0xFF0F4C81),
                            size: 20,
                          ),
                        ),
                        title: Text(
                          trip.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '${trip.startingPlace} → ${trip.destination} • ${trip.status.toUpperCase()}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: const Icon(Icons.chevron_right, size: 20),
                        onTap: () {
                          Navigator.pop(ctx);
                          ref
                              .read(tripsProvider.notifier)
                              .setActiveTrip(trip.id);
                          context.push('/trip-pay');
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(authProvider).user;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spaceLg,
            vertical: AppConstants.spaceSm,
          ),
          children: [
            // User Avatar & Bio Section
            Center(
              child: Column(
                children: [
                  GestureDetector(
                    onTap: () => _changeAvatar(context, ref),
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 46,
                          backgroundColor: theme.colorScheme.primaryContainer,
                          backgroundImage:
                              user?.photoUrl != null &&
                                  user!.photoUrl!.isNotEmpty
                              ? NetworkImage(user.photoUrl!)
                              : null,
                          child:
                              user?.photoUrl == null || user!.photoUrl!.isEmpty
                              ? Text(
                                  (user?.name.isNotEmpty == true
                                          ? user!.name[0]
                                          : 'U')
                                      .toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.w800,
                                    color: theme.colorScheme.primary,
                                  ),
                                )
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: CircleAvatar(
                            radius: 14,
                            backgroundColor: theme.colorScheme.primary,
                            child: const Icon(
                              Icons.camera_alt,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppConstants.spaceMd),
                  Text(
                    user?.name ?? 'Traveler',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user?.email ?? 'Collect moments, not things. ✨',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppConstants.spaceLg),

            // Stats Card (Trips, Places, Memories)
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spaceMd,
                  vertical: AppConstants.spaceLg,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildStatItem(
                        context,
                        label: 'Trips',
                        value: '${user?.tripCount ?? 0}',
                        icon: Icons.luggage_outlined,
                      ),
                    ),
                    Container(
                      height: 40,
                      width: 1,
                      color: theme.colorScheme.outlineVariant,
                    ),
                    Expanded(
                      child: _buildStatItem(
                        context,
                        label: 'Places',
                        value:
                            '${user?.tripCount != null && user!.tripCount > 0 ? user.tripCount * 2 : 0}',
                        icon: Icons.place_outlined,
                      ),
                    ),
                    Container(
                      height: 40,
                      width: 1,
                      color: theme.colorScheme.outlineVariant,
                    ),
                    Expanded(
                      child: _buildStatItem(
                        context,
                        label: 'Memories',
                        value: '0',
                        icon: Icons.photo_library_outlined,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppConstants.spaceLg),

            // Menu Section
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.luggage_outlined),
                    title: const Text(
                      'My Trips',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () => context.go('/trips'),
                  ),
                  Divider(
                    height: 1,
                    indent: 56,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  ListTile(
                    leading: const Icon(Icons.receipt_long_rounded),
                    title: const Text(
                      'My Trip Payments',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () => _showMyTripPaymentsModal(context, ref),
                  ),
                  Divider(
                    height: 1,
                    indent: 56,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  ListTile(
                    leading: const Icon(Icons.photo_library_outlined),
                    title: const Text(
                      'My Memories',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () => context.push('/memories'),
                  ),
                  Divider(
                    height: 1,
                    indent: 56,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  ListTile(
                    leading: const Icon(Icons.settings_outlined),
                    title: const Text(
                      'Settings',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Preferences & Profile settings'),
                        ),
                      );
                    },
                  ),
                  Divider(
                    height: 1,
                    indent: 56,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: const Text(
                      'Privacy',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () => _showPrivacyDialog(context, user?.email),
                  ),
                  Divider(
                    height: 1,
                    indent: 56,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  ListTile(
                    leading: const Icon(Icons.rate_review_outlined),
                    title: const Text(
                      'Send Beta Feedback',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'PILOT',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF92400E),
                        ),
                      ),
                    ),
                    onTap: () => BetaFeedbackSheet.show(context),
                  ),
                  Divider(
                    height: 1,
                    indent: 56,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  ListTile(
                    leading: const Icon(Icons.help_outline_rounded),
                    title: const Text(
                      'Help & Support',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'TripCrew Support: support@tripcrew.app',
                          ),
                        ),
                      );
                    },
                  ),
                  Divider(
                    height: 1,
                    indent: 56,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.logout_rounded,
                      color: Color(0xFFDC2626),
                    ),
                    title: const Text(
                      'Logout',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                    onTap: () async {
                      await ref.read(authProvider.notifier).signOut();
                      if (context.mounted) {
                        context.go('/welcome');
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppConstants.spaceLg),

            // App Footer
            Center(
              child: Column(
                children: [
                  Text(
                    '${AppConstants.appBetaName} • v${AppConstants.appVersion}',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    AppConstants.appTagline,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.7,
                      ),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppConstants.spaceLg),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(height: AppConstants.spaceXs),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
