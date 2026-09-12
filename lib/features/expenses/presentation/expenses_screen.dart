import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/core/services/analytics_service.dart';
import 'package:tripcrew/core/services/firebase_service.dart';
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

  void _listenToExpensesAndMembers() {
    final activeTrip = ref.read(activeTripProvider);
    if (activeTrip == null) {
      setState(() => _isLoading = false);
      return;
    }

    if (FirebaseService.isInitialized) {
      _expensesSub?.cancel();
      _membersSub?.cancel();

      // Listen to members
      _membersSub = FirebaseFirestore.instance
          .collection('trips')
          .doc(activeTrip.id)
          .collection('members')
          .snapshots()
          .listen(
            (snapshot) {
              final map = <String, String>{};
              for (final doc in snapshot.docs) {
                map[doc.id] = doc.data()['displayName'] as String? ?? 'Member';
              }
              if (mounted) setState(() => _memberNames = map);
            },
            onError: (_) {
              if (mounted) {
                setState(() {
                  _errorMessage =
                      'Could not sync crew members. Please check connection.';
                });
              }
            },
          );

      // Listen to expenses
      _expensesSub = FirebaseFirestore.instance
          .collection('trips')
          .doc(activeTrip.id)
          .collection('expenses')
          .orderBy('createdAt', descending: true)
          .snapshots()
          .listen(
            (snapshot) {
              final loaded = snapshot.docs
                  .map((doc) => ExpenseModel.fromMap(doc.data(), doc.id))
                  .toList();

              if (mounted) {
                setState(() {
                  _expenses = loaded;
                  _isLoading = false;
                  _errorMessage = null;
                });
              }
            },
            onError: (err) {
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _errorMessage =
                      'Could not sync expenses. Please check connection.';
                });
              }
            },
          );
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

                          if (FirebaseService.isInitialized) {
                            final batch = FirebaseFirestore.instance.batch();
                            final expenseRef = FirebaseFirestore.instance
                                .collection('trips')
                                .doc(tripId)
                                .collection('expenses')
                                .doc(newExpense.id);
                            final tripRef = FirebaseFirestore.instance
                                .collection('trips')
                                .doc(tripId);

                            batch.set(expenseRef, newExpense.toMap());
                            batch.update(tripRef, {
                              'totalSpendingPaise': FieldValue.increment(
                                amountPaise,
                              ),
                              'updatedAt': FieldValue.serverTimestamp(),
                            });

                            await batch.commit();
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
          onPressed: () => context.pop(),
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
                            trailing: Text(
                              CurrencyFormatter.formatUnits(exp.amountPaise),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
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
}
