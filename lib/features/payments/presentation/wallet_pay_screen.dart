import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/core/utils/currency_formatter.dart';

/// Screen 12: Pay with TripCrew Wallet screen matching UI design mockup.
class WalletPayScreen extends ConsumerStatefulWidget {
  const WalletPayScreen({super.key});

  @override
  ConsumerState<WalletPayScreen> createState() => _WalletPayScreenState();
}

class _WalletPayScreenState extends ConsumerState<WalletPayScreen> {
  int _selectedMethod = 0; // 0: Wallet, 1: UPI, 2: Card
  final double _amount = 1240.0;
  bool _isProcessing = false;

  void _processPayment() async {
    setState(() => _isProcessing = true);
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) {
      setState(() => _isProcessing = false);
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sandbox Simulation Complete ✨'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_circle_rounded,
                size: 56,
                color: Color(0xFF10B981),
              ),
              const SizedBox(height: 12),
              Text(
                'Settlement transfer of ${CurrencyFormatter.format(_amount)} simulated in Sandbox mode.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'No real money has moved. Verified 1% platform fee abstraction & signature contracts for Razorpay webhook integration.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.pop();
              },
              child: const Text('Done'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pay with TripCrew Wallet'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppConstants.spaceMd),

              // Sandbox Banner
              Container(
                margin: const EdgeInsets.only(bottom: AppConstants.spaceMd),
                padding: const EdgeInsets.all(AppConstants.spaceMd),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  border: Border.all(color: const Color(0xFFF59E0B)),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      color: Color(0xFFB45309),
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Development Sandbox • Simulating settlement flow without live fund movement.',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF92400E),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Settlement Recipient Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppConstants.spaceMd),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(
                            AppConstants.radiusMd,
                          ),
                        ),
                        child: Icon(
                          Icons.handshake_rounded,
                          color: theme.colorScheme.primary,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: AppConstants.spaceMd),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Crew Settlement',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              'Peer-to-peer group balance resolution',
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spaceLg),

              // Amount Card
              Card(
                color: theme.colorScheme.surfaceContainerLow,
                child: Padding(
                  padding: const EdgeInsets.all(AppConstants.spaceLg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Amount',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        CurrencyFormatter.format(_amount),
                        style: theme.textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spaceXl),

              // Payment Method Options
              Text(
                'Pay using',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppConstants.spaceSm),

              _buildPaymentOption(
                index: 0,
                title: 'TripCrew Wallet',
                subtitle: 'Sandbox simulated balance',
                icon: Icons.account_balance_wallet_rounded,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: AppConstants.spaceSm),
              _buildPaymentOption(
                index: 1,
                title: 'UPI (GPay, PhonePe, Paytm)',
                subtitle: 'Pay directly via linked bank account',
                icon: Icons.qr_code_2_rounded,
                color: const Color(0xFF10B981),
              ),
              const SizedBox(height: AppConstants.spaceSm),
              _buildPaymentOption(
                index: 2,
                title: 'Add New Card',
                subtitle: 'Credit / Debit Cards accepted',
                icon: Icons.credit_card_rounded,
                color: const Color(0xFF8B5CF6),
              ),

              const Spacer(),

              // Pay Now Button
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isProcessing ? null : _processPayment,
                  child: _isProcessing
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text('Pay ${CurrencyFormatter.format(_amount)} Now'),
                ),
              ),
              const SizedBox(height: AppConstants.spaceLg),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentOption({
    required int index,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = _selectedMethod == index;
    final theme = Theme.of(context);

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        side: BorderSide(
          color: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: isSelected ? 1.8 : 1.0,
        ),
      ),
      child: ListTile(
        onTap: () => setState(() => _selectedMethod = index),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: Icon(
          isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
          color: isSelected ? theme.colorScheme.primary : Colors.grey.shade400,
        ),
      ),
    );
  }
}
