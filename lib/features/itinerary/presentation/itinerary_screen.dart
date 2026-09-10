import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/core/services/analytics_service.dart';
import 'package:tripcrew/core/services/firebase_service.dart';
import 'package:tripcrew/core/widgets/app_empty_state.dart';
import 'package:tripcrew/features/itinerary/models/itinerary_item.dart';
import 'package:tripcrew/features/trips/providers/trips_provider.dart';

/// Screen 8: Itinerary timeline screen connected to real Firestore trips/{tripId}/itinerary.
class ItineraryScreen extends ConsumerStatefulWidget {
  const ItineraryScreen({super.key});

  @override
  ConsumerState<ItineraryScreen> createState() => _ItineraryScreenState();
}

class _ItineraryScreenState extends ConsumerState<ItineraryScreen> {
  int _selectedDay = 1;
  StreamSubscription? _sub;
  List<ItineraryItem> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _listenToItinerary();
  }

  void _listenToItinerary() {
    final activeTrip = ref.read(activeTripProvider);
    if (activeTrip == null) {
      setState(() => _isLoading = false);
      return;
    }

    if (FirebaseService.isInitialized) {
      _sub = FirebaseFirestore.instance
          .collection('trips')
          .doc(activeTrip.id)
          .collection('itinerary')
          .orderBy('order')
          .snapshots()
          .listen(
            (snapshot) {
              final loaded = snapshot.docs
                  .map((doc) => ItineraryItem.fromMap(doc.data(), doc.id))
                  .toList();

              if (mounted) {
                setState(() {
                  _items = loaded;
                  _isLoading = false;
                });
              }
            },
            onError: (_) {
              if (mounted) setState(() => _isLoading = false);
            },
          );
    } else {
      // Local fallback
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _showAddActivityDialog(String tripId) {
    final titleCtrl = TextEditingController();
    final timeCtrl = TextEditingController(text: '10:00 AM');
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
            onPressed: () async {
              if (titleCtrl.text.trim().isNotEmpty) {
                final newItem = ItineraryItem(
                  id: 'it_${DateTime.now().millisecondsSinceEpoch}',
                  dayNumber: _selectedDay,
                  time: timeCtrl.text,
                  title: titleCtrl.text.trim(),
                  placeName: placeCtrl.text.trim().isEmpty
                      ? null
                      : placeCtrl.text.trim(),
                  order: _items.length + 1,
                );

                if (FirebaseService.isInitialized) {
                  await FirebaseFirestore.instance
                      .collection('trips')
                      .doc(tripId)
                      .collection('itinerary')
                      .doc(newItem.id)
                      .set(newItem.toMap());
                } else {
                  setState(() => _items.add(newItem));
                }

                await AnalyticsService.logItineraryItemAdded(tripId);
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Add Activity'),
          ),
        ],
      ),
    );
  }

  void _toggleVisited(ItineraryItem item, String tripId) async {
    if (FirebaseService.isInitialized) {
      await FirebaseFirestore.instance
          .collection('trips')
          .doc(tripId)
          .collection('itinerary')
          .doc(item.id)
          .update({'isVisited': !item.isVisited});
    } else {
      setState(() {
        final idx = _items.indexWhere((i) => i.id == item.id);
        if (idx != -1) {
          _items[idx] = item.copyWith(isVisited: !item.isVisited);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeTrip = ref.watch(activeTripProvider);

    if (activeTrip == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Itinerary')),
        body: const Center(child: Text('No active trip selected.')),
      );
    }

    final dayItems = _items.where((i) => i.dayNumber == _selectedDay).toList();
    final maxDays = activeTrip.durationDays > 0 ? activeTrip.durationDays : 3;

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
                        activeTrip.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '${activeTrip.startingPlace} → ${activeTrip.destination}',
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
                  for (int d = 1; d <= maxDays; d++) ...[
                    _buildDayTab(d),
                    const SizedBox(width: AppConstants.spaceSm),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppConstants.spaceLg),

            // Timeline Items
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : dayItems.isEmpty
                  ? AppEmptyState(
                      icon: Icons.event_available_outlined,
                      title: 'No activities for Day $_selectedDay',
                      message:
                          'Tap "+ Add Activity" below to plan stops for this day.',
                      actionLabel: 'Add Stop',
                      onActionPressed: () =>
                          _showAddActivityDialog(activeTrip.id),
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
                                InkWell(
                                  onTap: () =>
                                      _toggleVisited(item, activeTrip.id),
                                  child: Container(
                                    width: 18,
                                    height: 18,
                                    decoration: BoxDecoration(
                                      color: item.isVisited
                                          ? const Color(0xFF10B981)
                                          : nodeColor,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: nodeColor.withValues(
                                            alpha: 0.3,
                                          ),
                                          blurRadius: 4,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
                                    child: item.isVisited
                                        ? const Icon(
                                            Icons.check,
                                            size: 12,
                                            color: Colors.white,
                                          )
                                        : null,
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
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                        decoration: item.isVisited
                                            ? TextDecoration.lineThrough
                                            : TextDecoration.none,
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
                  onPressed: () => _showAddActivityDialog(activeTrip.id),
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
