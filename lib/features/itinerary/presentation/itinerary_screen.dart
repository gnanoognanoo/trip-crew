import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/features/itinerary/models/itinerary_item.dart';
import 'package:tripcrew/features/trips/providers/trips_provider.dart';

/// Screen 8: Itinerary timeline screen matching UI design mockup.
class ItineraryScreen extends ConsumerStatefulWidget {
  const ItineraryScreen({super.key});

  @override
  ConsumerState<ItineraryScreen> createState() => _ItineraryScreenState();
}

class _ItineraryScreenState extends ConsumerState<ItineraryScreen> {
  int _selectedDay = 1;

  final List<ItineraryItem> _items = [
    const ItineraryItem(
      id: 'it_1',
      dayNumber: 1,
      time: '07:00 AM',
      title: 'Start from Chennai',
      notes: 'Meet at Central Station pickup point',
      order: 1,
    ),
    const ItineraryItem(
      id: 'it_2',
      dayNumber: 1,
      time: '12:30 PM',
      title: 'Lunch Stop',
      placeName: 'Highway Dhaba',
      order: 2,
    ),
    const ItineraryItem(
      id: 'it_3',
      dayNumber: 1,
      time: '03:00 PM',
      title: 'Baga Beach',
      placeName: 'North Goa',
      notes: 'Check-in and beach walk',
      order: 3,
    ),
    const ItineraryItem(
      id: 'it_4',
      dayNumber: 1,
      time: '06:30 PM',
      title: 'Sunset Point',
      placeName: 'Anjuna Clifftop',
      order: 4,
    ),
    const ItineraryItem(
      id: 'it_5',
      dayNumber: 1,
      time: '08:00 PM',
      title: 'Dinner',
      placeName: 'Britto’s Shack',
      order: 5,
    ),
    const ItineraryItem(
      id: 'it_6',
      dayNumber: 2,
      time: '08:30 AM',
      title: 'Scuba Diving & Watersports',
      placeName: 'Grand Island',
      order: 1,
    ),
    const ItineraryItem(
      id: 'it_7',
      dayNumber: 2,
      time: '02:00 PM',
      title: 'Old Goa Churches & Spice Farm',
      placeName: 'Old Goa',
      order: 2,
    ),
    const ItineraryItem(
      id: 'it_8',
      dayNumber: 3,
      time: '10:00 AM',
      title: 'Flea Market & Souvenir Shopping',
      placeName: 'Anjuna Market',
      order: 1,
    ),
  ];

  void _showAddActivityDialog() {
    final titleCtrl = TextEditingController();
    final timeCtrl = TextEditingController(text: '11:00 AM');
    final placeCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add Day $_selectedDay Activity'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: 'Activity Name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: timeCtrl,
              decoration: const InputDecoration(
                labelText: 'Time (e.g. 02:30 PM)',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: placeCtrl,
              decoration: const InputDecoration(
                labelText: 'Place / Location (optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (titleCtrl.text.trim().isNotEmpty) {
                setState(() {
                  _items.add(
                    ItineraryItem(
                      id: 'it_${DateTime.now().millisecondsSinceEpoch}',
                      dayNumber: _selectedDay,
                      time: timeCtrl.text,
                      title: titleCtrl.text.trim(),
                      placeName: placeCtrl.text.trim().isEmpty
                          ? null
                          : placeCtrl.text.trim(),
                      order: _items.length + 1,
                    ),
                  );
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text('Add Activity'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeTrip = ref.watch(activeTripProvider);
    final dayItems = _items.where((i) => i.dayNumber == _selectedDay).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Itinerary'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Subheader
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spaceLg,
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(
                      Icons.surfing_rounded,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: AppConstants.spaceSm),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        activeTrip?.name ?? 'Goa Trip',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '15 - 17 Oct 2024',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppConstants.spaceMd),

            // Day Selector Tabs
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spaceLg,
              ),
              child: Row(
                children: [
                  _buildDayTab(1),
                  const SizedBox(width: AppConstants.spaceSm),
                  _buildDayTab(2),
                  const SizedBox(width: AppConstants.spaceSm),
                  _buildDayTab(3),
                  const SizedBox(width: AppConstants.spaceSm),
                  InkWell(
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Add Day functionality')),
                      );
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.add, size: 16),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppConstants.spaceLg),

            // Timeline Items
            Expanded(
              child: dayItems.isEmpty
                  ? const Center(
                      child: Text('No activities added for this day.'),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppConstants.spaceLg,
                      ),
                      itemCount: dayItems.length,
                      itemBuilder: (context, index) {
                        final item = dayItems[index];
                        final isLast = index == dayItems.length - 1;
                        final colors = [
                          const Color(0xFFF97316),
                          const Color(0xFF1E6091),
                          const Color(0xFF10B981),
                          const Color(0xFFFF6B4A),
                          const Color(0xFF8B5CF6),
                        ];
                        final nodeColor = colors[index % colors.length];

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Timeline Axis
                            Column(
                              children: [
                                Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: nodeColor,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: nodeColor.withValues(alpha: 0.3),
                                        blurRadius: 4,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                ),
                                if (!isLast)
                                  Container(
                                    width: 2,
                                    height: 70,
                                    color: theme.colorScheme.outlineVariant,
                                  ),
                              ],
                            ),
                            const SizedBox(width: AppConstants.spaceMd),

                            // Content Details
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppConstants.spaceLg,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.time,
                                      style: TextStyle(
                                        color: theme.colorScheme.primary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      item.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                      ),
                                    ),
                                    if (item.placeName != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        item.placeName!,
                                        style: TextStyle(
                                          color: theme
                                              .colorScheme
                                              .onSurfaceVariant,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),

            // Bottom Add Activity Button
            Padding(
              padding: const EdgeInsets.all(AppConstants.spaceLg),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _showAddActivityDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Activity'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayTab(int day) {
    final isSelected = _selectedDay == day;
    final theme = Theme.of(context);

    return InkWell(
      onTap: () => setState(() => _selectedDay = day),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1E6091) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF1E6091)
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: Text(
          'Day $day',
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? Colors.white
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
