import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/features/checklist/models/checklist_item.dart';

/// Screen 9: Packing Checklist screen matching UI design mockup.
class ChecklistScreen extends ConsumerStatefulWidget {
  const ChecklistScreen({super.key});

  @override
  ConsumerState<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends ConsumerState<ChecklistScreen> {
  int _selectedFilter = 0; // 0: My List, 1: Shared, 2: Assigned

  final List<ChecklistItem> _items = [
    // Clothes
    const ChecklistItem(
      id: 'c1',
      title: 'T-shirts',
      category: 'Clothes',
      isCompleted: true,
    ),
    const ChecklistItem(
      id: 'c2',
      title: 'Shorts',
      category: 'Clothes',
      isCompleted: true,
    ),
    const ChecklistItem(
      id: 'c3',
      title: 'Jacket',
      category: 'Clothes',
      isCompleted: false,
    ),
    const ChecklistItem(
      id: 'c4',
      title: 'Socks',
      category: 'Clothes',
      isCompleted: false,
    ),

    // Travel Essentials
    const ChecklistItem(
      id: 't1',
      title: 'ID Card',
      category: 'Travel Essentials',
      isCompleted: true,
    ),
    const ChecklistItem(
      id: 't2',
      title: 'Power Bank',
      category: 'Travel Essentials',
      isCompleted: false,
      assignedToMemberName: 'Arun',
      assignedToUid: 'user_arun_102',
    ),
    const ChecklistItem(
      id: 't3',
      title: 'Charger',
      category: 'Travel Essentials',
      isCompleted: false,
    ),
    const ChecklistItem(
      id: 't4',
      title: 'Travel Adapter',
      category: 'Travel Essentials',
      isCompleted: false,
    ),

    // Health
    const ChecklistItem(
      id: 'h1',
      title: 'First Aid Kit',
      category: 'Health',
      isCompleted: false,
      assignedToMemberName: 'Rahul',
      assignedToUid: 'user_rahul_103',
    ),
    const ChecklistItem(
      id: 'h2',
      title: 'Medicines',
      category: 'Health',
      isCompleted: false,
    ),
  ];

  void _showAddItemDialog() {
    final titleCtrl = TextEditingController();
    String category = 'Clothes';
    String? assigned;

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
                  labelText: 'Assign To (Optional)',
                ),
                items: const [
                  DropdownMenuItem(
                    value: null,
                    child: Text('Unassigned / Self'),
                  ),
                  DropdownMenuItem(value: 'Arun', child: Text('Arun')),
                  DropdownMenuItem(value: 'Rahul', child: Text('Rahul')),
                  DropdownMenuItem(value: 'Praveen', child: Text('Praveen')),
                ],
                onChanged: (val) => setDialogState(() => assigned = val),
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
                      ChecklistItem(
                        id: 'c_${DateTime.now().millisecondsSinceEpoch}',
                        title: titleCtrl.text.trim(),
                        category: category,
                        assignedToMemberName: assigned,
                      ),
                    );
                  });
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Group items by category
    final categories = ['Clothes', 'Travel Essentials', 'Health'];

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
            // Filter Chips
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

            // Categorized Items
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spaceLg,
                  vertical: 8,
                ),
                children: categories.map((cat) {
                  final catItems = _items.where((item) {
                    if (item.category != cat) {
                      return false;
                    }
                    if (_selectedFilter == 1) {
                      return item.isShared;
                    }
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
                                        color: theme.colorScheme.secondary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    )
                                  : null,
                              onChanged: (val) {
                                setState(() {
                                  final idx = _items.indexWhere(
                                    (i) => i.id == item.id,
                                  );
                                  if (idx != -1) {
                                    _items[idx] = item.copyWith(
                                      isCompleted: val ?? false,
                                    );
                                  }
                                });
                              },
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

            // Bottom Add Item Button
            Padding(
              padding: const EdgeInsets.all(AppConstants.spaceLg),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _showAddItemDialog,
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
