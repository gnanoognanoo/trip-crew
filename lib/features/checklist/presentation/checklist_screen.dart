import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/core/services/analytics_service.dart';
import 'package:tripcrew/core/services/supabase_service.dart';
import 'package:tripcrew/core/widgets/app_empty_state.dart';
import 'package:tripcrew/core/widgets/app_error_state.dart';
import 'package:tripcrew/features/checklist/models/checklist_item.dart';
import 'package:tripcrew/features/trips/providers/trips_provider.dart';

/// Screen 9: Packing Checklist screen connected to Supabase PostgreSQL checklist_items.
class ChecklistScreen extends ConsumerStatefulWidget {
  const ChecklistScreen({super.key});

  @override
  ConsumerState<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends ConsumerState<ChecklistScreen> {
  int _selectedFilter = 0; // 0: My List, 1: Shared, 2: Assigned
  StreamSubscription? _sub;
  List<ChecklistItem> _items = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _listenToChecklist();
  }

  void _listenToChecklist() async {
    final activeTrip = ref.read(activeTripProvider);
    if (activeTrip == null) {
      setState(() => _isLoading = false);
      return;
    }

    if (SupabaseService.isInitialized) {
      try {
        final res = await SupabaseService.client
            .from('checklist_items')
            .select()
            .eq('trip_id', activeTrip.id)
            .order('created_at', ascending: true);

        final loaded = res
            .map((doc) => ChecklistItem.fromMap(Map<String, dynamic>.from(doc), doc['id'] as String))
            .toList();

        if (mounted) {
          setState(() {
            _items = loaded;
            _isLoading = false;
            _errorMessage = null;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Could not load checklist. Check your connection.';
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

  void _showAddItemDialog(String tripId) {
    final titleCtrl = TextEditingController();
    String category = 'Clothes';
    String? assigned;
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Checklist Item'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Item Name'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: const [
                  DropdownMenuItem(value: 'Clothes', child: Text('Clothes')),
                  DropdownMenuItem(
                    value: 'Travel Essentials',
                    child: Text('Travel Essentials'),
                  ),
                  DropdownMenuItem(value: 'Health', child: Text('Health')),
                  DropdownMenuItem(
                    value: 'Electronics',
                    child: Text('Electronics'),
                  ),
                  DropdownMenuItem(
                    value: 'Trip Specific',
                    child: Text('Trip Specific'),
                  ),
                ],
                onChanged: (val) => setDialogState(() => category = val!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: assigned,
                decoration: const InputDecoration(
                  labelText: 'Assign To Member (Optional)',
                ),
                items: const [
                  DropdownMenuItem(
                    value: null,
                    child: Text('Unassigned / Shared'),
                  ),
                  DropdownMenuItem(value: 'Self', child: Text('Myself')),
                  DropdownMenuItem(
                    value: 'Crew Member',
                    child: Text('Crew Member'),
                  ),
                ],
                onChanged: (val) => setDialogState(() => assigned = val),
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
                        final newItem = ChecklistItem(
                          id: 'c_${DateTime.now().millisecondsSinceEpoch}',
                          title: titleCtrl.text.trim(),
                          category: category,
                          assignedToMemberName: assigned,
                          isShared: assigned == null,
                        );

                        if (SupabaseService.isInitialized) {
                          await SupabaseService.client.from('checklist_items').insert({
                            'id': newItem.id,
                            'trip_id': tripId,
                            'title': newItem.title,
                            'is_completed': false,
                            'assigned_to_name': assigned,
                            'created_at': DateTime.now().toIso8601String(),
                          });
                          setState(() => _items.add(newItem));
                        } else {
                          setState(() => _items.add(newItem));
                        }

                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        if (ctx.mounted) {
                          setDialogState(() => isSubmitting = false);
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Failed to add item. Check connection.',
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
                  : const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleChecklistItem(ChecklistItem item, String tripId) async {
    final updated = !item.isCompleted;

    if (SupabaseService.isInitialized) {
      await SupabaseService.client
          .from('checklist_items')
          .update({'is_completed': updated})
          .eq('id', item.id);

      setState(() {
        final idx = _items.indexWhere((i) => i.id == item.id);
        if (idx != -1) {
          _items[idx] = item.copyWith(isCompleted: updated);
        }
      });
    } else {
      setState(() {
        final idx = _items.indexWhere((i) => i.id == item.id);
        if (idx != -1) {
          _items[idx] = item.copyWith(isCompleted: updated);
        }
      });
    }

    if (updated) {
      await AnalyticsService.logChecklistItemCompleted(tripId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeTrip = ref.watch(activeTripProvider);

    if (activeTrip == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Packing Checklist')),
        body: const Center(child: Text('No active trip selected.')),
      );
    }

    final categories = [
      'Clothes',
      'Travel Essentials',
      'Health',
      'Electronics',
      'Trip Specific',
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Packing Checklist'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spaceLg,
                vertical: 8,
              ),
              child: Row(
                children: [
                  _buildFilterChip('My List', 0),
                  const SizedBox(width: AppConstants.spaceSm),
                  _buildFilterChip('Shared', 1),
                  const SizedBox(width: AppConstants.spaceSm),
                  _buildFilterChip('Assigned', 2),
                ],
              ),
            ),

            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                  ? AppErrorState(
                      title: 'Could not load checklist',
                      message: _errorMessage!,
                      onRetry: () {
                        setState(() {
                          _isLoading = true;
                          _errorMessage = null;
                        });
                        _listenToChecklist();
                      },
                    )
                  : _items.isEmpty
                  ? AppEmptyState(
                      icon: Icons.checklist_rtl_rounded,
                      title: 'Checklist is empty',
                      message:
                          'Add items your crew needs to pack for ${activeTrip.name}.',
                      actionLabel: 'Add Item',
                      onActionPressed: () => _showAddItemDialog(activeTrip.id),
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppConstants.spaceLg,
                        vertical: 8,
                      ),
                      children: categories.map((cat) {
                        final catItems = _items.where((item) {
                          if (item.category != cat) return false;
                          if (_selectedFilter == 1) return item.isShared;
                          if (_selectedFilter == 2) {
                            return item.assignedToMemberName != null;
                          }
                          return true;
                        }).toList();

                        if (catItems.isEmpty) return const SizedBox.shrink();

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                cat,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                            Card(
                              child: Column(
                                children: catItems.map((item) {
                                  return CheckboxListTile(
                                    value: item.isCompleted,
                                    activeColor: const Color(0xFF10B981),
                                    title: Text(
                                      item.title,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        decoration: item.isCompleted
                                            ? TextDecoration.lineThrough
                                            : TextDecoration.none,
                                        color: item.isCompleted
                                            ? theme.colorScheme.onSurfaceVariant
                                            : theme.colorScheme.onSurface,
                                      ),
                                    ),
                                    subtitle: item.assignedToMemberName != null
                                        ? Text(
                                            'Assigned to ${item.assignedToMemberName}',
                                            style: TextStyle(
                                              color:
                                                  theme.colorScheme.secondary,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          )
                                        : null,
                                    onChanged: (_) => _toggleChecklistItem(
                                      item,
                                      activeTrip.id,
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                            const SizedBox(height: AppConstants.spaceMd),
                          ],
                        );
                      }).toList(),
                    ),
            ),

            Padding(
              padding: const EdgeInsets.all(AppConstants.spaceLg),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _showAddItemDialog(activeTrip.id),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Item'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, int index) {
    final isSelected = _selectedFilter == index;
    final theme = Theme.of(context);

    return InkWell(
      onTap: () => setState(() => _selectedFilter = index),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
          label,
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
