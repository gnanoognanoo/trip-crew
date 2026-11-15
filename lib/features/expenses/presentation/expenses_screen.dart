import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/core/services/analytics_service.dart';
import 'package:tripcrew/core/services/supabase_service.dart';
import 'package:tripcrew/core/utils/currency_formatter.dart';
import 'package:tripcrew/core/widgets/app_empty_state.dart';
import 'package:tripcrew/core/widgets/app_error_state.dart';
import 'package:tripcrew/features/auth/providers/auth_provider.dart';
import 'package:tripcrew/features/expenses/models/expense_model.dart';
import 'package:tripcrew/features/expenses/utils/settlement_calculator.dart';
import 'package:tripcrew/features/trips/providers/trips_provider.dart';

/// Screen 10: Expense Tracker screen connected to real Firestore trips/{tripId}/expenses.
class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  int _selectedTab = 0; // 0: All, 1: My Expenses, 2: Settlements
  StreamSubscription? _expensesSub;
  StreamSubscription? _membersSub;

  List<ExpenseModel> _expenses = [];
  Map<String, String> _memberNames = {};
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _listenToExpensesAndMembers();
  }

  void _listenToExpensesAndMembers() async {
    final activeTrip = ref.read(activeTripProvider);
    if (activeTrip == null) {
      setState(() => _isLoading = false);
      return;
    }

    if (SupabaseService.isInitialized) {
      try {
        final membersRes = await SupabaseService.client
            .from('trip_members')
            .select('user_id, role')
            .eq('trip_id', activeTrip.id);

        final map = <String, String>{};
        final uids = membersRes.map((m) => m['user_id'] as String).toSet().toList();
        if (uids.isNotEmpty) {
          try {
            final profilesRes = await SupabaseService.client
                .from('profiles')
                .select('id, display_name, full_name')
                .inFilter('id', uids);
            for (final p in profilesRes) {
              final pid = p['id'] as String;
              final name = p['display_name'] as String? ?? p['full_name'] as String? ?? 'Member';
              map[pid] = name;
            }
          } catch (_) {}
        }
        for (final m in membersRes) {
          final uid = m['user_id'] as String;
          map.putIfAbsent(uid, () => 'Member');
        }

        final expRes = await SupabaseService.client
            .from('expenses')
            .select()
            .eq('trip_id', activeTrip.id)
            .order('created_at', ascending: false);

        final loaded = expRes
            .map((e) => ExpenseModel.fromMap(Map<String, dynamic>.from(e), e['id'] as String))
            .toList();

        if (mounted) {
          setState(() {
            _memberNames = map;
            _expenses = loaded;
            _isLoading = false;
            _errorMessage = null;
          });
        }
      } catch (err) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Could not sync expenses. Please check connection.';
          });
        }
      }
    } else {
      final user = ref.read(authProvider).user;
      setState(() {
        _memberNames = {user?.uid ?? 'creator': user?.name ?? 'You'};
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _expensesSub?.cancel();
    _membersSub?.cancel();
    super.dispose();
  }

  void _showAddExpenseDialog(String tripId) {
    final descCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    String category = 'Food';
    final user = ref.read(authProvider).user;
    String paidBy =
        user?.uid ??
        (_memberNames.keys.isNotEmpty ? _memberNames.keys.first : 'self');

    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Expense'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: descCtrl,
                enabled: !isSubmitting,
                decoration: const InputDecoration(
                  labelText: 'Description (e.g. Dinner)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: amountCtrl,
                enabled: !isSubmitting,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount (₹)',
                  prefixText: '₹ ',
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: const [
                  DropdownMenuItem(value: 'Food', child: Text('Food')),
                  DropdownMenuItem(value: 'Stay', child: Text('Stay')),
                  DropdownMenuItem(value: 'Fuel', child: Text('Fuel')),
                  DropdownMenuItem(value: 'Travel', child: Text('Travel')),
                  DropdownMenuItem(value: 'Tickets', child: Text('Tickets')),
                  DropdownMenuItem(value: 'Shopping', child: Text('Shopping')),
                  DropdownMenuItem(value: 'Other', child: Text('Other')),
                ],
                onChanged: isSubmitting
                    ? null
                    : (val) => setDialogState(() => category = val!),
              ),
              const SizedBox(height: 8),
              if (_memberNames.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: _memberNames.containsKey(paidBy)
                      ? paidBy
                      : _memberNames.keys.first,
                  decoration: const InputDecoration(labelText: 'Paid By'),
                  items: _memberNames.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: isSubmitting
                      ? null
                      : (val) => setDialogState(() => paidBy = val!),
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
                      final amount = double.tryParse(amountCtrl.text) ?? 0.0;
                      if (descCtrl.text.trim().isNotEmpty && amount > 0) {
                        setDialogState(() => isSubmitting = true);
                        try {
                          final amountPaise = CurrencyFormatter.toSmallestUnit(
                            amount,
                          );
                          final payerName =
                              _memberNames[paidBy] ?? user?.name ?? 'Member';

                          final newExpense = ExpenseModel(
                            id: 'e_${DateTime.now().millisecondsSinceEpoch}',
                            description: descCtrl.text.trim(),
                            amountPaise: amountPaise,
                            category: category,
                            paidByUid: paidBy,
                            paidByName: payerName,
                            participantUids: _memberNames.keys.toList(),
                            createdBy: user?.uid ?? 'guest',
                            createdAt: DateTime.now(),
                          );

                          if (SupabaseService.isInitialized) {
                            await SupabaseService.client.from('expenses').insert({
                              'id': newExpense.id,
                              'trip_id': tripId,
                              'title': descCtrl.text.trim(),
                              'amount_paise': amountPaise,
                              'paid_by_user_id': paidBy,
                              'paid_by_name': payerName,
                              'category': category,
                              'split_type': 'EQUAL',
                              'created_at': DateTime.now().toIso8601String(),
                            });
                            setState(() => _expenses.insert(0, newExpense));
                          } else {
                            setState(() => _expenses.insert(0, newExpense));
                          }

                          await AnalyticsService.logExpenseAdded(
                            tripId,
                            category: category,
                            paymentSource: 'manual',
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                        } finally {
                          if (ctx.mounted) {
                            setDialogState(() => isSubmitting = false);
                          }
                        }
                      }
                    },
              child: isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Add Expense'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeTrip = ref.watch(activeTripProvider);
    final currentUser = ref.watch(authProvider).user;

    if (activeTrip == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Expenses')),
        body: const Center(child: Text('No active trip selected.')),
      );
    }

    final filteredExpenses = _selectedTab == 1
        ? _expenses.where((e) => e.paidByUid == currentUser?.uid).toList()
        : _expenses;

    // Calculate totals dynamically
    int totalPaise = 0;
    final Map<String, int> memberSpending = {};
    for (final m in _memberNames.keys) {
      memberSpending[m] = 0;
    }
    for (final exp in _expenses) {
      totalPaise += exp.amountPaise;
      memberSpending[exp.paidByUid] =
          (memberSpending[exp.paidByUid] ?? 0) + exp.amountPaise;
    }

    final settlements = SettlementCalculator.calculateSettlements(
      expenses: _expenses,
      memberNames: _memberNames,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expenses'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () { if (context.canPop()) { context.pop(); } else { context.go('/workspace'); } },
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Tabs
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spaceLg,
                vertical: 8,
              ),
              child: Row(
                children: [
                  _buildFilterChip('All', 0),
                  const SizedBox(width: AppConstants.spaceSm),
                  _buildFilterChip('My Expenses', 1),
                  const SizedBox(width: AppConstants.spaceSm),
                  _buildFilterChip('Settlements', 2),
                ],
              ),
            ),

            if (_selectedTab != 2) ...[
              // Total Spending Card
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spaceLg,
                  vertical: 8,
                ),
                child: Card(
                  color: theme.colorScheme.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.all(AppConstants.spaceLg),
                    child: Column(
                      children: [
                        Text(
                          'Total Spending',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          CurrencyFormatter.formatUnits(totalPaise),
                          style: theme.textTheme.headlineLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                            color: const Color(0xFF1E6091),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${activeTrip.name} • ${_expenses.length} ${_expenses.length == 1 ? "expense" : "expenses"}',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Expenses List
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _errorMessage != null
                    ? AppErrorState(
                        title: 'Could not load expenses',
                        message: _errorMessage!,
                        onRetry: () {
                          setState(() {
                            _isLoading = true;
                            _errorMessage = null;
                          });
                          _listenToExpensesAndMembers();
                        },
                      )
                    : filteredExpenses.isEmpty
                    ? AppEmptyState(
                        icon: Icons.receipt_long_rounded,
                        title: _selectedTab == 1
                            ? 'No expenses logged by you'
                            : 'No expenses recorded',
                        message:
                            'Tap "+ Add Expense" below to start tracking shared crew costs.',
                        actionLabel: 'Add Expense',
                        onActionPressed: () =>
                            _showAddExpenseDialog(activeTrip.id),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppConstants.spaceLg,
                          vertical: 8,
                        ),
                        itemCount: filteredExpenses.length,
                        separatorBuilder: (_, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final exp = filteredExpenses[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  theme.colorScheme.primaryContainer,
                              child: Icon(
                                _getCategoryIcon(exp.category),
                                color: theme.colorScheme.primary,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              exp.description,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              'Paid by ${exp.paidByName} • Equal Split',
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  CurrencyFormatter.formatUnits(exp.amountPaise),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert, size: 18),
                                  onSelected: (val) {
                                    if (val == 'edit') {
                                      _showEditExpenseDialog(exp, activeTrip.id);
                                    } else if (val == 'delete') {
                                      _deleteExpense(exp);
                                    }
                                  },
                                  itemBuilder: (ctx) => [
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: Text('Edit Expense'),
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
                          );
                        },
                      ),
              ),
            ] else ...[
              // Settlements Tab View
              Expanded(
                child: settlements.isEmpty
                    ? const AppEmptyState(
                        icon: Icons.check_circle_outline,
                        title: 'All balances settled!',
                        message:
                            'No pending debts or settlement transfers needed for this trip.',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(AppConstants.spaceLg),
                        itemCount: settlements.length,
                        itemBuilder: (context, index) {
                          final st = settlements[index];
                          return Card(
                            margin: const EdgeInsets.only(
                              bottom: AppConstants.spaceSm,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(
                                AppConstants.spaceMd,
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: Colors.red.shade100,
                                    child: Text(
                                      st.fromName.isNotEmpty
                                          ? st.fromName[0].toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                        color: Colors.red.shade900,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: AppConstants.spaceSm),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        RichText(
                                          text: TextSpan(
                                            style: theme.textTheme.bodyMedium,
                                            children: [
                                              TextSpan(
                                                text: st.fromName,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const TextSpan(text: ' owes '),
                                              TextSpan(
                                                text: st.toName,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Text(
                                          'Direct settlement suggestion',
                                          style: TextStyle(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        CurrencyFormatter.formatUnits(
                                          st.amountPaise,
                                        ),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFFE25B3E),
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      FilledButton.tonal(
                                        onPressed: () => _showSettleUpDialog(st, activeTrip.id),
                                        style: FilledButton.styleFrom(
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 2,
                                          ),
                                        ),
                                        child: const Text(
                                          'Settle Up',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],

            // Action Buttons
            Padding(
              padding: const EdgeInsets.all(AppConstants.spaceLg),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _showAddExpenseDialog(activeTrip.id),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Expense'),
                    ),
                  ),
                  const SizedBox(height: AppConstants.spaceSm),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() => _selectedTab = 2);
                      },
                      child: const Text('View Settlements'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Food':
        return Icons.restaurant_rounded;
      case 'Stay':
        return Icons.hotel_rounded;
      case 'Fuel':
        return Icons.local_gas_station_rounded;
      case 'Travel':
        return Icons.directions_car_rounded;
      case 'Tickets':
        return Icons.confirmation_number_rounded;
      case 'Shopping':
        return Icons.shopping_bag_rounded;
      default:
        return Icons.receipt_rounded;
    }
  }

  Widget _buildFilterChip(String label, int index) {
    final isSelected = _selectedTab == index;
    final theme = Theme.of(context);

    return InkWell(
      onTap: () => setState(() => _selectedTab = index),
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

  void _showEditExpenseDialog(ExpenseModel expense, String tripId) {
    final descCtrl = TextEditingController(text: expense.description);
    final amtCtrl = TextEditingController(
      text: (expense.amountPaise / 100.0).toStringAsFixed(0),
    );
    String category = expense.category;
    String paidBy = expense.paidByUid;
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Edit Expense'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amtCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Amount (₹)',
                    prefixText: '₹ ',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: const [
                    DropdownMenuItem(value: 'Food', child: Text('Food')),
                    DropdownMenuItem(value: 'Stay', child: Text('Stay')),
                    DropdownMenuItem(value: 'Fuel', child: Text('Fuel')),
                    DropdownMenuItem(value: 'Travel', child: Text('Travel')),
                    DropdownMenuItem(value: 'Tickets', child: Text('Tickets')),
                    DropdownMenuItem(value: 'Shopping', child: Text('Shopping')),
                    DropdownMenuItem(value: 'General', child: Text('General')),
                  ],
                  onChanged: (val) => setDialogState(() => category = val!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: paidBy,
                  decoration: const InputDecoration(labelText: 'Paid By'),
                  items: _memberNames.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: (val) => setDialogState(() => paidBy = val!),
                ),
              ],
            ),
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
                      final amountPaise =
                          ((double.tryParse(amtCtrl.text.trim()) ?? 0) * 100).round();
                      if (descCtrl.text.trim().isEmpty || amountPaise <= 0) {
                        return;
                      }

                      setDialogState(() => isSubmitting = true);
                      try {
                        final payerName = _memberNames[paidBy] ?? 'Member';
                        if (SupabaseService.isInitialized) {
                          await SupabaseService.client
                              .from('expenses')
                              .update({
                                'title': descCtrl.text.trim(),
                                'amount_paise': amountPaise,
                                'category': category,
                                'paid_by_user_id': paidBy,
                                'paid_by_name': payerName,
                              })
                              .eq('id', expense.id);
                        }

                        final updatedExp = expense.copyWith(
                          description: descCtrl.text.trim(),
                          amountPaise: amountPaise,
                          category: category,
                          paidByUid: paidBy,
                          paidByName: payerName,
                        );

                        final idx = _expenses.indexWhere((e) => e.id == expense.id);
                        if (idx != -1) {
                          setState(() {
                            _expenses[idx] = updatedExp;
                          });
                        }

                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Expense updated successfully!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          setDialogState(() => isSubmitting = false);
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text('Failed to update expense: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              child: isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteExpense(ExpenseModel expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Expense?'),
        content: Text(
          'Delete "${expense.description}" (${CurrencyFormatter.formatUnits(expense.amountPaise)})?',
        ),
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
              .from('expenses')
              .delete()
              .eq('id', expense.id);
        }
        setState(() {
          _expenses.removeWhere((e) => e.id == expense.id);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Expense deleted.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete expense: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _showSettleUpDialog(SettlementTransaction st, String tripId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Record Settlement?'),
        content: Text(
          'Confirm that ${st.fromName} paid ${CurrencyFormatter.formatUnits(st.amountPaise)} directly to ${st.toName} to settle their balance.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final settlementId =
                    'stl_${DateTime.now().millisecondsSinceEpoch}';
                if (SupabaseService.isInitialized) {
                  await SupabaseService.client.from('settlements').insert({
                    'id': settlementId,
                    'trip_id': tripId,
                    'from_user_id': st.fromUid,
                    'from_user_name': st.fromName,
                    'to_user_id': st.toUid,
                    'to_user_name': st.toName,
                    'amount_paise': st.amountPaise,
                    'is_settled': true,
                    'created_at': DateTime.now().toIso8601String(),
                  });
                }

                final settlementExpense = ExpenseModel(
                  id: 'exp_${DateTime.now().millisecondsSinceEpoch}',
                  description: 'Settlement: ${st.fromName} → ${st.toName}',
                  amountPaise: st.amountPaise,
                  category: 'General',
                  paidByUid: st.fromUid,
                  paidByName: st.fromName,
                  participantUids: [st.toUid],
                  createdBy: st.fromUid,
                  createdAt: DateTime.now(),
                );

                if (SupabaseService.isInitialized) {
                  await SupabaseService.client.from('expenses').insert({
                    'id': settlementExpense.id,
                    'trip_id': tripId,
                    'title': settlementExpense.description,
                    'amount_paise': settlementExpense.amountPaise,
                    'paid_by_user_id': settlementExpense.paidByUid,
                    'paid_by_name': settlementExpense.paidByName,
                    'category': 'General',
                    'split_type': 'DIRECT',
                    'created_at': DateTime.now().toIso8601String(),
                  });
                }

                setState(() {
                  _expenses.insert(0, settlementExpense);
                });

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Settlement of ${CurrencyFormatter.formatUnits(st.amountPaise)} recorded successfully!',
                      ),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to record settlement: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Confirm Settle Up'),
          ),
        ],
      ),
    );
  }
}
