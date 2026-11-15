import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/core/services/analytics_service.dart';
import 'package:tripcrew/core/services/supabase_service.dart';
import 'package:tripcrew/core/widgets/app_empty_state.dart';
import 'package:tripcrew/core/widgets/app_error_state.dart';
import 'package:tripcrew/features/ai/presentation/ai_assistant_dialog.dart';
import 'package:tripcrew/features/itinerary/models/itinerary_item.dart';
import 'package:tripcrew/features/trips/providers/trips_provider.dart';

/// Screen 8: Itinerary timeline screen connected to Supabase PostgreSQL itinerary_items.
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
  String? _errorMessage;

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

    if (SupabaseService.isInitialized) {
      try {
        _sub?.cancel();
        _sub = SupabaseService.client
            .from('itinerary_items')
            .stream(primaryKey: ['id'])
            .eq('trip_id', activeTrip.id)
            .listen(
              (data) {
                final loaded = data
                    .map((doc) => ItineraryItem.fromMap(
                          Map<String, dynamic>.from(doc),
                          doc['id'] as String,
                        ))
                    .toList();
                loaded.sort((a, b) {
                  final dayCmp = a.dayNumber.compareTo(b.dayNumber);
                  if (dayCmp != 0) return dayCmp;
                  final orderCmp = a.order.compareTo(b.order);
                  if (orderCmp != 0) return orderCmp;
                  return a.time.compareTo(b.time);
                });

                if (mounted) {
                  setState(() {
                    _items = loaded;
                    _isLoading = false;
                    _errorMessage = null;
                  });
                }
              },
              onError: (e) async {
                try {
                  final res = await SupabaseService.client
                      .from('itinerary_items')
                      .select()
                      .eq('trip_id', activeTrip.id)
                      .order('created_at', ascending: true);
                  final loaded = res
                      .map((doc) => ItineraryItem.fromMap(
                            Map<String, dynamic>.from(doc),
                            doc['id'] as String,
                          ))
                      .toList();
                  if (mounted) {
                    setState(() {
                      _items = loaded;
                      _isLoading = false;
                      _errorMessage = null;
                    });
                  }
                } catch (_) {
                  if (mounted) {
                    setState(() {
                      _isLoading = false;
                      _errorMessage =
                          'Could not load itinerary. Check your connection.';
                    });
                  }
                }
              },
            );
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Could not load itinerary. Check your connection.';
          });
        }
      }
    } else {
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
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
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
              onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      if (titleCtrl.text.trim().isEmpty) return;
                      setDialogState(() => isSubmitting = true);
                      try {
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

                        final notesPayload = jsonEncode({
                          'day': newItem.dayNumber,
                          'time': newItem.time,
                        });

                        if (SupabaseService.isInitialized) {
                          try {
                            await SupabaseService.client.from('itinerary_items').insert({
                              'id': newItem.id,
                              'trip_id': tripId,
                              'title': newItem.title,
                              'location': newItem.placeName,
                              'day_number': newItem.dayNumber,
                              'time': newItem.time,
                              'notes': notesPayload,
                              'is_completed': false,
                              'created_at': DateTime.now().toIso8601String(),
                            });
                          } catch (_) {
                            await SupabaseService.client.from('itinerary_items').insert({
                              'id': newItem.id,
                              'trip_id': tripId,
                              'title': newItem.title,
                              'location': newItem.placeName,
                              'notes': notesPayload,
                              'is_completed': false,
                              'created_at': DateTime.now().toIso8601String(),
                            });
                          }
                          setState(() => _items.add(newItem));
                        } else {
                          setState(() => _items.add(newItem));
                        }

                        await AnalyticsService.logItineraryItemAdded(tripId);
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        if (ctx.mounted) {
                          setDialogState(() => isSubmitting = false);
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Failed to add activity. Check connection.',
                              ),
                            ),
                          );
                        }
                      }
                    },
              child: isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Add Activity'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditActivityDialog(ItineraryItem item, String tripId) {
    final titleCtrl = TextEditingController(text: item.title);
    final timeCtrl = TextEditingController(text: item.time);
    final placeCtrl = TextEditingController(text: item.placeName ?? '');
    int day = item.dayNumber;
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Edit Activity'),
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
                decoration: const InputDecoration(labelText: 'Time'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: placeCtrl,
                decoration: const InputDecoration(labelText: 'Location (optional)'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      if (titleCtrl.text.trim().isEmpty) return;
                      setDialogState(() => isSubmitting = true);
                      try {
                        final updated = item.copyWith(
                          title: titleCtrl.text.trim(),
                          time: timeCtrl.text.trim(),
                          placeName: placeCtrl.text.trim().isEmpty
                              ? null
                              : placeCtrl.text.trim(),
                          dayNumber: day,
                        );

                        final notesPayload = jsonEncode({
                          'day': updated.dayNumber,
                          'time': updated.time,
                        });

                        if (SupabaseService.isInitialized) {
                          try {
                            await SupabaseService.client
                                .from('itinerary_items')
                                .update({
                                  'title': updated.title,
                                  'location': updated.placeName,
                                  'day_number': updated.dayNumber,
                                  'time': updated.time,
                                  'notes': notesPayload,
                                })
                                .eq('id', item.id);
                          } catch (_) {
                            await SupabaseService.client
                                .from('itinerary_items')
                                .update({
                                  'title': updated.title,
                                  'location': updated.placeName,
                                  'notes': notesPayload,
                                })
                                .eq('id', item.id);
                          }
                        }

                        setState(() {
                          final idx = _items.indexWhere((i) => i.id == item.id);
                          if (idx != -1) _items[idx] = updated;
                        });

                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Activity updated successfully!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          setDialogState(() => isSubmitting = false);
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text('Failed to update activity: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              child: isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteActivity(ItineraryItem item, String tripId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Activity?'),
        content: Text('Are you sure you want to delete "${item.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        if (SupabaseService.isInitialized) {
          await SupabaseService.client
              .from('itinerary_items')
              .delete()
              .eq('id', item.id);
        }
        setState(() {
          _items.removeWhere((i) => i.id == item.id);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Activity deleted.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete activity: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _toggleVisited(ItineraryItem item, String tripId) async {
    final nextState = !item.isVisited;
    if (SupabaseService.isInitialized) {
      await SupabaseService.client
          .from('itinerary_items')
          .update({'is_completed': nextState})
          .eq('id', item.id);

      setState(() {
        final idx = _items.indexWhere((i) => i.id == item.id);
        if (idx != -1) {
          _items[idx] = item.copyWith(isVisited: nextState);
        }
      });
    } else {
      setState(() {
        final idx = _items.indexWhere((i) => i.id == item.id);
        if (idx != -1) {
          _items[idx] = item.copyWith(isVisited: nextState);
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
          onPressed: () { if (context.canPop()) { context.pop(); } else { context.go('/workspace'); } },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome_rounded),
            color: const Color(0xFFFFB800),
            tooltip: 'AI Trip Packages & Planner',
            onPressed: () => AiAssistantDialog.show(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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

            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                  ? AppErrorState(
                      title: 'Could not load itinerary',
                      message: _errorMessage!,
                      onRetry: () {
                        setState(() {
                          _isLoading = true;
                          _errorMessage = null;
                        });
                        _listenToItinerary();
                      },
                    )
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

                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppConstants.spaceLg,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
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
                                    PopupMenuButton<String>(
                                      icon: const Icon(Icons.more_vert, size: 18),
                                      onSelected: (val) {
                                        if (val == 'edit') {
                                          _showEditActivityDialog(item, activeTrip.id);
                                        } else if (val == 'delete') {
                                          _deleteActivity(item, activeTrip.id);
                                        }
                                      },
                                      itemBuilder: (ctx) => [
                                        const PopupMenuItem(
                                          value: 'edit',
                                          child: Text('Edit Activity'),
                                        ),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Text(
                                            'Delete',
                                            style: TextStyle(color: Colors.red),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),

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
