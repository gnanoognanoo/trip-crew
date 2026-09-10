import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/core/utils/currency_formatter.dart';
import 'package:tripcrew/features/payments/models/wallet_model.dart';

/// Screen 11: TripCrew Wallet screen matching UI design mockup.
class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  double _balance = 0.0;
  final List<WalletTransaction> _transactions = [];

  void _showAddMoneyDialog() {
    final amountCtrl = TextEditingController(text: '1000');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Money to Wallet'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter amount to load via UPI or NetBanking:'),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount (₹)',
                prefixText: '₹ ',
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
              final added = double.tryParse(amountCtrl.text) ?? 0.0;
              if (added > 0) {
                setState(() {
                  _balance += added;
                  _transactions.insert(
                    0,
                    WalletTransaction(
                      id: 'tx_${DateTime.now().millisecondsSinceEpoch}',
                      title: 'Added Money',
                      subtitle: 'UPI Payment Gateway',
                      amount: added,
                      isCredit: true,
                      date: DateTime.now(),
                    ),
                  );
                });
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Added ${CurrencyFormatter.format(added)} to TripCrew Wallet!',
                    ),
                  ),
                );
              }
            },
            child: const Text('Add Money'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('TripCrew Wallet'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppConstants.spaceSm),

              // Sandbox / Regulatory Compliance Banner
              Container(
                margin: const EdgeInsets.only(bottom: AppConstants.spaceMd),
                padding: const EdgeInsets.all(AppConstants.spaceMd),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  border: Border.all(color: const Color(0xFFF59E0B)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      color: Color(0xFFB45309),
                      size: 20,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Development / Sandbox Simulation',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF92400E),
                              fontSize: 13,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'TripCrew is not an unlicensed stored-value wallet. Firebase never holds customer funds. Real transactions are routed through authorized payment gateways.',
                            style: TextStyle(
                              color: Color(0xFF78350F),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Gradient Wallet Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppConstants.spaceLg),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF2E86AB), Color(0xFF8B5CF6)],
                  ),
                  borderRadius: BorderRadius.circular(AppConstants.radiusXl),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total Balance',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        InkWell(
                          onTap: _showAddMoneyDialog,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.25),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.add,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      CurrencyFormatter.format(_balance),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            '1% Platform Fee Applied on Settlements',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppConstants.spaceLg),

              // Action Buttons Row (Add Money, Send, Request)
              Row(
                children: [
                  _buildActionBtn(
                    context,
                    title: 'Add Money',
                    icon: Icons.account_balance_wallet_outlined,
                    onTap: _showAddMoneyDialog,
                  ),
                  const SizedBox(width: AppConstants.spaceSm),
                  _buildActionBtn(
                    context,
                    title: 'Send',
                    icon: Icons.send_rounded,
                    onTap: () => context.push('/wallet-pay'),
                  ),
                  const SizedBox(width: AppConstants.spaceSm),
                  _buildActionBtn(
                    context,
                    title: 'Request',
                    icon: Icons.call_received_rounded,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Payment request created!'),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: AppConstants.spaceXl),

              // Recent Transactions Section
              Text(
                'Recent Transactions',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppConstants.spaceSm),
              _transactions.isEmpty
                  ? const Card(
                      child: Padding(
                        padding: EdgeInsets.all(AppConstants.spaceLg),
                        child: Center(
                          child: Text(
                            'No sandbox transactions yet.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ),
                    )
                  : Card(
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _transactions.length,
                        separatorBuilder: (_, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final tx = _transactions[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: tx.isCredit
                                  ? const Color(
                                      0xFF10B981,
                                    ).withValues(alpha: 0.15)
                                  : const Color(
                                      0xFFEF4444,
                                    ).withValues(alpha: 0.15),
                              child: Icon(
                                tx.isCredit
                                    ? Icons.arrow_downward_rounded
                                    : Icons.arrow_upward_rounded,
                                color: tx.isCredit
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFFEF4444),
                                size: 20,
                              ),
                            ),
                            title: Text(
                              tx.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              tx.subtitle,
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                            trailing: Text(
                              '${tx.isCredit ? '+' : '-'} ${CurrencyFormatter.format(tx.amount)}',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: tx.isCredit
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFF0F172A),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
              const SizedBox(height: AppConstants.spaceLg),

              Center(
                child: TextButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Full transaction statement'),
                      ),
                    );
                  },
                  child: const Text('View All Transactions'),
                ),
              ),
              const SizedBox(height: AppConstants.spaceLg),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionBtn(
    BuildContext context, {
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              Icon(icon, color: theme.colorScheme.primary, size: 24),
              const SizedBox(height: 6),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
