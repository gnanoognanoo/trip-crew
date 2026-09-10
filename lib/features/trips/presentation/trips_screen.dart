import 'package:flutter/material.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/core/widgets/app_empty_state.dart';

/// Trips Screen placeholder with filter tabs (Active, Upcoming, Completed)
/// and action buttons.
class TripsScreen extends StatelessWidget {
  const TripsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Trips'),
          bottom: TabBar(
            indicatorColor: theme.colorScheme.primary,
            indicatorWeight: 3,
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
            labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            tabs: const [
              Tab(text: 'Active'),
              Tab(text: 'Upcoming'),
              Tab(text: 'Completed'),
            ],
          ),
        ),
        body: Column(
          children: [
            // Action Buttons Bar
            Padding(
              padding: const EdgeInsets.all(AppConstants.spaceMd),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Create Trip will be available in Phase 3'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Create Trip'),
                    ),
                  ),
                  const SizedBox(width: AppConstants.spaceSm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Join Trip will be available in Phase 4'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: const Icon(Icons.group_add_outlined, size: 18),
                      label: const Text('Join Trip'),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Tab Views
            const Expanded(
              child: TabBarView(
                children: [
                  AppEmptyState(
                    icon: Icons.explore_off_outlined,
                    title: 'No active trips',
                    message: 'When you are currently travelling with your crew, your live trip will appear here.',
                  ),
                  AppEmptyState(
                    icon: Icons.calendar_today_outlined,
                    title: 'No upcoming trips',
                    message: 'Create a new trip or join one with an invite code to start collaborating.',
                  ),
                  AppEmptyState(
                    icon: Icons.check_circle_outline,
                    title: 'No completed trips',
                    message: 'Past journeys and shared recap memories will be archived here.',
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
