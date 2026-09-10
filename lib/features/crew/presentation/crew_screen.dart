import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/core/services/firebase_service.dart';
import 'package:tripcrew/core/widgets/app_empty_state.dart';
import 'package:tripcrew/features/auth/providers/auth_provider.dart';
import 'package:tripcrew/features/crew/models/crew_member.dart';
import 'package:tripcrew/features/trips/providers/trips_provider.dart';

/// Screen 7: Crew Members screen connected to real Firestore subcollection.
class CrewScreen extends ConsumerStatefulWidget {
  const CrewScreen({super.key});

  @override
  ConsumerState<CrewScreen> createState() => _CrewScreenState();
}

class _CrewScreenState extends ConsumerState<CrewScreen> {
  StreamSubscription? _sub;
  List<CrewMember> _members = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _listenToCrew();
  }

  void _listenToCrew() {
    final activeTrip = ref.read(activeTripProvider);
    if (activeTrip == null) {
      setState(() => _isLoading = false);
      return;
    }

    if (FirebaseService.isInitialized) {
      _sub = FirebaseFirestore.instance
          .collection('trips')
          .doc(activeTrip.id)
          .collection('members')
          .snapshots()
          .listen(
            (snapshot) {
              final loaded = snapshot.docs
                  .map((doc) => CrewMember.fromMap(doc.data(), doc.id))
                  .toList();

              // Sort owner first, then by joinedAt
              loaded.sort((a, b) {
                if (a.isOwner) return -1;
                if (b.isOwner) return 1;
                return a.joinedAt.compareTo(b.joinedAt);
              });

              if (mounted) {
                setState(() {
                  _members = loaded;
                  _isLoading = false;
                });
              }
            },
            onError: (_) {
              if (mounted) setState(() => _isLoading = false);
            },
          );
    } else {
      // Local fallback for offline mode
      final currentUser = ref.read(authProvider).user;
      setState(() {
        _members = [
          CrewMember(
            uid: currentUser?.uid ?? 'creator',
            displayName: currentUser?.name ?? 'Trip Owner',
            role: 'owner',
            isOnline: true,
            joinedAt: DateTime.now(),
          ),
        ];
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _showQrDialog(String inviteCode) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Trip QR Code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 180,
              height: 180,
              child: QrImageView(
                data: 'https://tripcrew.app/join/$inviteCode',
                version: QrVersions.auto,
                size: 180,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              inviteCode,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _removeMember(CrewMember member, String tripId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${member.displayName}?'),
        content: const Text('They will no longer have access to this trip.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true && FirebaseService.isInitialized) {
      await FirebaseFirestore.instance
          .collection('trips')
          .doc(tripId)
          .collection('members')
          .doc(member.uid)
          .delete();
      await FirebaseFirestore.instance.collection('trips').doc(tripId).update({
        'memberCount': FieldValue.increment(-1),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeTrip = ref.watch(activeTripProvider);
    final currentUser = ref.watch(authProvider).user;
    final inviteCode = activeTrip?.inviteCode ?? 'TRIP-DEMO';
    final isCurrentOwner = activeTrip?.ownerId == currentUser?.uid;

    if (activeTrip == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Crew Members')),
        body: const Center(child: Text('No active trip selected.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Crew Members'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top Trip Summary & Invite Action
            Padding(
              padding: const EdgeInsets.all(AppConstants.spaceLg),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppConstants.spaceMd),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Icon(
                          Icons.groups_rounded,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: AppConstants.spaceMd),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              activeTrip.name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${_members.length} ${_members.length == 1 ? "member" : "members"}',
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () => _showQrDialog(inviteCode),
                        icon: const Icon(
                          Icons.person_add_alt_1_rounded,
                          size: 16,
                        ),
                        label: const Text('Invite'),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Members List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _members.isEmpty
                  ? const AppEmptyState(
                      icon: Icons.group_off_outlined,
                      title: 'No crew members yet',
                      message:
                          'Share your invite code to bring friends into this workspace.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppConstants.spaceLg,
                      ),
                      itemCount: _members.length,
                      separatorBuilder: (_, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final member = _members[index];
                        final isMe = member.uid == currentUser?.uid;

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 4,
                          ),
                          leading: Stack(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor:
                                    theme.colorScheme.surfaceContainerHigh,
                                child: Text(
                                  member.displayName.isNotEmpty
                                      ? member.displayName[0].toUpperCase()
                                      : 'M',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                              ),
                              if (member.isOnline)
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          title: Row(
                            children: [
                              Text(
                                isMe
                                    ? '${member.displayName} (You)'
                                    : member.displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (member.isOwner) ...[
                                const SizedBox(width: 6),
                                const Icon(
                                  Icons.workspace_premium_rounded,
                                  size: 18,
                                  color: Colors.amber,
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text(
                            member.isOwner ? 'Trip Owner' : 'Member',
                            style: TextStyle(
                              color: member.isOwner
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                              fontWeight: member.isOwner
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              fontSize: 12,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (member.isOnline)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF10B981,
                                    ).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text(
                                    'Online',
                                    style: TextStyle(
                                      color: Color(0xFF10B981),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              // Owner can remove member (cannot remove self)
                              if (isCurrentOwner && !member.isOwner)
                                IconButton(
                                  icon: const Icon(
                                    Icons.remove_circle_outline,
                                    color: Colors.redAccent,
                                    size: 20,
                                  ),
                                  onPressed: () =>
                                      _removeMember(member, activeTrip.id),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),

            // Bottom "Invite via" section
            Padding(
              padding: const EdgeInsets.all(AppConstants.spaceLg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Invite via',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppConstants.spaceSm),
                  Row(
                    children: [
                      _buildInviteOption(
                        context,
                        title: 'Code',
                        icon: Icons.pin_outlined,
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: inviteCode));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Code $inviteCode copied!')),
                          );
                        },
                      ),
                      const SizedBox(width: AppConstants.spaceSm),
                      _buildInviteOption(
                        context,
                        title: 'Link',
                        icon: Icons.link_rounded,
                        onTap: () {
                          Clipboard.setData(
                            ClipboardData(
                              text: 'https://tripcrew.app/join/$inviteCode',
                            ),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Invite link copied!'),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: AppConstants.spaceSm),
                      _buildInviteOption(
                        context,
                        title: 'QR Code',
                        icon: Icons.qr_code_rounded,
                        onTap: () => _showQrDialog(inviteCode),
                      ),
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

  Widget _buildInviteOption(
    BuildContext context, {
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              Icon(icon, size: 22, color: theme.colorScheme.primary),
              const SizedBox(height: 4),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
