import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/core/utils/currency_formatter.dart';
import 'package:tripcrew/features/expenses/models/expense_model.dart';
import 'package:tripcrew/features/expenses/utils/settlement_calculator.dart';
import 'package:tripcrew/features/trips/providers/trips_provider.dart';

/// Screen 10: Expense Tracker screen matching UI design mockup.
class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  int _selectedTab = 0; // 0: All, 1: My Expenses, 2: Settlements

  final List<ExpenseModel> _expenses = [
    ExpenseModel(
      id: 'e1',
      description: 'Resort Stay & Booking',
      amountPaise: 800000, // ₹8,000
      category: 'Stay',
      paidByUid: 'demo_kowshik_101',
      paidByName: 'Kowshik',
      participantUids: [
        'demo_kowshik_101',
        'user_arun_102',
        'user_rahul_103',
        'user_praveen_104',
      ],
      createdBy: 'demo_kowshik_101',
      createdAt: DateTime(2024, 10, 15, 12, 0),
    ),
    ExpenseModel(
      id: 'e2',
      description: 'Fuel & Highway Tolls',
      amountPaise: 430000, // ₹4,300
      category: 'Fuel',
      paidByUid: 'user_arun_102',
      paidByName: 'Arun',
      participantUids: [
        'demo_kowshik_101',
        'user_arun_102',
        'user_rahul_103',
        'user_praveen_104',
      ],
      createdBy: 'user_arun_102',
      createdAt: DateTime(2024, 10, 15, 16, 30),
    ),
    ExpenseModel(
      id: 'e3',
      description: 'Beachside Dinner & Drinks',
      amountPaise: 400000, // ₹4,000
      category: 'Food',
      paidByUid: 'user_praveen_104',
      paidByName: 'Praveen',
      participantUids: [
        'demo_kowshik_101',
        'user_arun_102',
        'user_rahul_103',
        'user_praveen_104',
      ],
      createdBy: 'user_praveen_104',
      createdAt: DateTime(2024, 10, 15, 21, 0),
    ),
    ExpenseModel(
      id: 'e4',
      description: 'Scuba Diving Passes',
      amountPaise: 215000, // ₹2,150
      category: 'Tickets',
      paidByUid: 'user_rahul_103',
      paidByName: 'Rahul',
      participantUids: [
        'demo_kowshik_101',
        'user_arun_102',
        'user_rahul_103',
        'user_praveen_104',
      ],
      createdBy: 'user_rahul_103',
      createdAt: DateTime(2024, 10, 16, 10, 0),
    ),
  ];

  final Map<String, String> _memberNames = {
    'demo_kowshik_101': 'Kowshik',
    'user_arun_102': 'Arun',
    'user_rahul_103': 'Rahul',
    'user_praveen_104': 'Praveen',
  };

  void _showAddExpenseDialog() {
    final descCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    String category = 'Food';
    String paidBy = 'demo_kowshik_101';

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
                decoration: const InputDecoration(
                  labelText: 'Description (e.g. Dinner)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
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
                onChanged: (val) => setDialogState(() => category = val!),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: paidBy,
                decoration: const InputDecoration(labelText: 'Paid By'),
                items: _memberNames.entries
                    .map(
                      (e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                    )
                    .toList(),
                onChanged: (val) => setDialogState(() => paidBy = val!),
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
                final amount = double.tryParse(amountCtrl.text) ?? 0.0;
                if (descCtrl.text.trim().isNotEmpty && amount > 0) {
                  setState(() {
                    _expenses.add(
                      ExpenseModel(
                        id: 'e_${DateTime.now().millisecondsSinceEpoch}',
                        description: descCtrl.text.trim(),
                        amountPaise: CurrencyFormatter.toSmallestUnit(amount),
                        category: category,
                        paidByUid: paidBy,
                        paidByName: _memberNames[paidBy] ?? 'Member',
                        participantUids: _memberNames.keys.toList(),
                        createdBy: 'demo_kowshik_101',
                        createdAt: DateTime.now(),
                      ),
                    );
                  });
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Add Expense'),
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

    // Calculate member spending totals
    final Map<String, int> memberSpending = {};
    for (final m in _memberNames.keys) {
      memberSpending[m] = 0;
    }
    int totalPaise = 0;
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
                          '${activeTrip?.name ?? 'Goa Trip'} • ${_expenses.length} transactions',
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

              // Members Breakdown List
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.spaceLg,
                    vertical: 8,
                  ),
                  children: [
                    Text(
                      _selectedTab == 0
                          ? 'Member Contributions'
                          : 'My Logged Expenses',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppConstants.spaceSm),
                    Card(
                      child: Column(
                        children: _memberNames.entries.map((entry) {
                          final spentPaise = memberSpending[entry.key] ?? 0;
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  theme.colorScheme.primaryContainer,
                              child: Text(
                                entry.value[0],
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                            title: Text(
                              entry.value,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              'Equal Split • ${activeTrip?.name ?? 'Trip'}',
                            ),
                            trailing: Text(
                              CurrencyFormatter.formatUnits(spentPaise),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Settlements Tab View
              Expanded(
                child: settlements.isEmpty
                    ? const Center(child: Text('All balances are settled up!'))
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
                                      st.fromName[0],
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
                      onPressed: _showAddExpenseDialog,
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
