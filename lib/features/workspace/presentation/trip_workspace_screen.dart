import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/core/utils/currency_formatter.dart';
import 'package:tripcrew/features/ai/presentation/ai_assistant_dialog.dart';
import 'package:tripcrew/features/trips/providers/trips_provider.dart';

/// Screen for the dedicated per-trip workspace hub.
/// Isolates the workspace navigation from global app-level tabs.
class TripWorkspaceScreen extends ConsumerWidget {
  const TripWorkspaceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final trip = ref.watch(activeTripProvider);

    if (trip == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Trip Workspace')),
        body: const Center(child: Text('No trip selected.')),
      );
    }

    final dateFormat = DateFormat('dd MMM yyyy');

    return Scaffold(
      appBar: AppBar(
        title: Text(trip.name),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome_rounded),
            color: theme.colorScheme.secondary,
            tooltip: 'AI Travel Assistant',
            onPressed: () => AiAssistantDialog.show(context),
          ),
          IconButton(
            icon: const Icon(Icons.share_rounded),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: trip.inviteCode));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Invite code ${trip.inviteCode} copied!'),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceLg),
          children: [
            const SizedBox(height: AppConstants.spaceSm),

            // Overview Banner
            Container(
              padding: const EdgeInsets.all(AppConstants.spaceLg),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E6091), Color(0xFF184E77)],
                ),
                borderRadius: BorderRadius.circular(AppConstants.radiusXl),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${trip.daysToGo} days to go',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        'Code: ${trip.inviteCode}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    trip.name,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${trip.startingPlace} → ${trip.destination}',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today,
                        size: 14,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${dateFormat.format(trip.startDate)} - ${dateFormat.format(trip.endDate)} (${trip.durationDays} Days)',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppConstants.spaceLg),

            // Overview Metric Row
            Row(
              children: [
                Expanded(
                  child: _buildMetricTile(
                    theme,
                    title: 'Budget',
                    value: CurrencyFormatter.format(trip.budget),
                    icon: Icons.savings_outlined,
                  ),
                ),
                const SizedBox(width: AppConstants.spaceSm),
                Expanded(
                  child: _buildMetricTile(
                    theme,
                    title: 'Crew Count',
                    value: '${trip.memberCount} Members',
                    icon: Icons.groups_outlined,
                  ),
                ),
                const SizedBox(width: AppConstants.spaceSm),
                Expanded(
                  child: _buildMetricTile(
                    theme,
                    title: 'Type',
                    value: trip.tripType,
                    icon: Icons.hiking_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spaceXl),

            // Modules Navigation Hub
            Text(
              'Trip Workspace Modules',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppConstants.spaceSm),

            _buildModuleItem(
              context,
              title: 'Smart Itinerary',
              subtitle: 'Day-by-day activities and timeline',
              icon: Icons.calendar_month_rounded,
              color: const Color(0xFFEF4444),
              onTap: () => context.push('/itinerary'),
            ),
            _buildModuleItem(
              context,
              title: 'Crew & Members',
              subtitle: 'Manage group members and invite links',
              icon: Icons.groups_rounded,
              color: const Color(0xFF06B6D4),
              onTap: () => context.push('/crew'),
            ),
            _buildModuleItem(
              context,
              title: 'TripCrew Pay',
              subtitle: 'Shared Trip Pot • Contribute & pay together',
              icon: Icons.savings_rounded,
              color: const Color(0xFF10B981),
              onTap: () => context.push('/trip-pay'),
            ),
            _buildModuleItem(
              context,
              title: 'Shared Expenses & Settlements',
              subtitle: 'Track spending and auto-minimize debt',
              icon: Icons.account_balance_wallet_rounded,
              color: const Color(0xFFF59E0B),
              onTap: () => context.push('/expenses'),
            ),
            _buildModuleItem(
              context,
              title: 'Packing Checklist',
              subtitle: 'Categorized items, personal & assigned gear',
              icon: Icons.backpack_rounded,
              color: const Color(0xFFF97316),
              onTap: () => context.push('/checklist'),
            ),
            _buildModuleItem(
              context,
              title: 'Live Crew Location',
              subtitle: 'Realtime crew radar, proximity & regrouping',
              icon: Icons.radar_rounded,
              color: const Color(0xFF10B981),
              onTap: () => context.push('/live-location'),
            ),
            _buildModuleItem(
              context,
              title: 'Trip Pulse',
              subtitle: 'Share needs: Hungry, Tired, Fuel, Restroom',
              icon: Icons.favorite_rounded,
              color: const Color(0xFFEC4899),
              onTap: () => context.push('/pulse'),
            ),
            _buildModuleItem(
              context,
              title: 'Shared Memories Gallery',
              subtitle: 'Crew photos, videos and daily timeline',
              icon: Icons.photo_library_rounded,
              color: const Color(0xFF8B5CF6),
              onTap: () => context.push('/memories'),
            ),
            _buildModuleItem(
              context,
              title: 'Map — Coming Soon',
              subtitle: 'Routes, places & recommendations',
              icon: Icons.map_rounded,
              color: const Color(0xFF3B82F6),
              onTap: () => context.push('/map'),
            ),
            _buildModuleItem(
              context,
              title: 'Budget Explorer',
              subtitle: 'Discover food, cafes, fuel & restrooms nearby',
              icon: Icons.explore_rounded,
              color: const Color(0xFF3B82F6),
              onTap: () => context.push('/explore'),
            ),
            _buildModuleItem(
              context,
              title: 'Safety & Emergency SOS',
              subtitle: 'Instant alert beacon and nearby emergency services',
              icon: Icons.shield_rounded,
              color: const Color(0xFFDC2626),
              onTap: () => context.push('/safety'),
            ),
            _buildModuleItem(
              context,
              title: 'Trip Recap & Analytics',
              subtitle: 'Story replay, distances, and expenses breakdown',
              icon: Icons.insights_rounded,
              color: const Color(0xFF6366F1),
              onTap: () => context.push('/recap'),
            ),
            const SizedBox(height: AppConstants.space2xl),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile(
    ThemeData theme, {
    required String title,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          Text(
            title,
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModuleItem(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: AppConstants.spaceSm),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        trailing: const Icon(Icons.chevron_right, size: 18),
      ),
    );
  }
}
