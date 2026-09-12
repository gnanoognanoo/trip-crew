import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/core/services/analytics_service.dart';
import 'package:tripcrew/core/services/firebase_service.dart';
import 'package:tripcrew/core/utils/currency_formatter.dart';
import 'package:tripcrew/features/trip_pay/models/payment_intent.dart';
import 'package:tripcrew/features/trip_pay/models/payment_status.dart';
import 'package:tripcrew/features/trip_pay/models/trip_pay_fee_config.dart';
import 'package:tripcrew/features/trip_pay/providers/sandbox_payment_provider.dart';
import 'package:tripcrew/features/trip_pay/providers/trip_pay_notifier.dart';
import 'package:tripcrew/features/trips/providers/trips_provider.dart';

/// Screen for adding a contribution (share) to the shared Trip Pot via UPI rails.
class AddContributionScreen extends ConsumerStatefulWidget {
  const AddContributionScreen({super.key});

  @override
  ConsumerState<AddContributionScreen> createState() =>
      _AddContributionScreenState();
}

class _AddContributionScreenState extends ConsumerState<AddContributionScreen> {
  final _amountController = TextEditingController();
  String? _clientRequestId;

  @override
  void initState() {
    super.initState();
    _clientRequestId =
        'ctr_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}';
    final activeTrip = ref.read(activeTripProvider);
    if (activeTrip != null) {
      AnalyticsService.logTripPotContributionStarted(activeTrip.id);
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  int get _amountPaise {
    final amount = double.tryParse(_amountController.text) ?? 0;
    return CurrencyFormatter.toSmallestUnit(amount);
  }

  int get _feePaise => TripPayFeeConfig.calculateFeePaise(_amountPaise);
  int get _totalPaise => TripPayFeeConfig.calculateTotalPaise(_amountPaise);

  /// Initiates the UPI Contribution flow and displays the interactive state sheet.
  Future<void> _startContributionFlow() async {
    final amountPaise = _amountPaise;
    if (amountPaise <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount.')),
      );
      return;
    }

    if (!FirebaseService.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('TripCrew Pay requires an active connection.'),
        ),
      );
      return;
    }

    final activeTrip = ref.read(activeTripProvider);
    if (activeTrip == null) return;

    final notifier = ref.read(tripPayProvider.notifier);

    // Step 1: Create contribution intent (CREATED state)
    final intent = await notifier.initiateContributionIntent(
      tripId: activeTrip.id,
      amountPaise: amountPaise,
      clientRequestId: _clientRequestId!,
    );

    if (intent == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ref.read(tripPayProvider).error ??
                  'Could not initialize payment.',
            ),
          ),
        );
      }
      return;
    }

    if (!mounted) return;

    // Step 2: Open UPI Payment Sheet (WAITING FOR PAYMENT -> VERIFYING -> SUCCESS/FAILED)
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _UpiPaymentSheet(
        tripId: activeTrip.id,
        intent: intent,
        onSuccess: () {
          AnalyticsService.logTripPotContributionCompleted(activeTrip.id);
          Navigator.pop(sheetCtx, true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Added ${CurrencyFormatter.formatUnits(amountPaise)} to the Trip Pot!',
              ),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
          context.pop();
        },
        onCancelOrFailed: (reason) {
          Navigator.pop(sheetCtx, false);
          _clientRequestId =
              'ctr_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(reason),
              backgroundColor: Colors.grey.shade800,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeTrip = ref.watch(activeTripProvider);
    final tripPayState = ref.watch(tripPayProvider);

    final bool isCrewResolving =
        tripPayState.isLoading && tripPayState.memberNames.isEmpty;
    final int? resolvedCrewCount = tripPayState.memberNames.isNotEmpty
        ? tripPayState.memberNames.length
        : (activeTrip != null && activeTrip.memberCount > 1
              ? activeTrip.memberCount
              : (isCrewResolving ? null : (activeTrip?.memberCount ?? 1)));

    final double? suggestedAmount =
        (activeTrip != null &&
            resolvedCrewCount != null &&
            resolvedCrewCount > 0)
        ? (activeTrip.budget / resolvedCrewCount).roundToDouble()
        : null;

    if (_amountController.text.isEmpty &&
        suggestedAmount != null &&
        suggestedAmount > 0) {
      _amountController.text = suggestedAmount.toStringAsFixed(0);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Your Share'),
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
              const SizedBox(height: AppConstants.spaceSm),

              // Sandbox Test Mode Badge
              Container(
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
                        'PAYMENT TEST MODE • Sandbox UPI Simulator • No real money is transferred.',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF92400E),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppConstants.spaceLg),

              // Trip Info Card
              if (activeTrip != null) ...[
                Card(
                  color: theme.colorScheme.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.all(AppConstants.spaceMd),
                    child: Column(
                      children: [
                        _infoRow(
                          theme,
                          'Trip Budget',
                          CurrencyFormatter.format(activeTrip.budget),
                        ),
                        const SizedBox(height: 4),
                        _infoRow(
                          theme,
                          'Crew',
                          isCrewResolving || resolvedCrewCount == null
                              ? 'Syncing crew...'
                              : '$resolvedCrewCount ${resolvedCrewCount == 1 ? "member" : "members"}',
                        ),
                        const SizedBox(height: 4),
                        _infoRow(
                          theme,
                          'Suggested contribution',
                          isCrewResolving || suggestedAmount == null
                              ? 'Calculating suggested share...'
                              : CurrencyFormatter.format(suggestedAmount),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: AppConstants.spaceLg),

              // Amount Input
              Text(
                'Contribution Amount',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppConstants.spaceSm),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                enabled: !tripPayState.isProcessing,
                decoration: const InputDecoration(
                  prefixText: '₹ ',
                  border: OutlineInputBorder(),
                  hintText: 'Enter amount',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppConstants.spaceMd),

              // Transparent 1% Fee Card
              Card(
                color: theme.colorScheme.surfaceContainerLow,
                child: Padding(
                  padding: const EdgeInsets.all(AppConstants.spaceMd),
                  child: Column(
                    children: [
                      _infoRow(
                        theme,
                        'Contribution to Trip Pot',
                        CurrencyFormatter.formatUnits(_amountPaise),
                      ),
                      const SizedBox(height: 4),
                      _infoRow(
                        theme,
                        'Platform service fee (${TripPayFeeConfig.feePercentageLabel})',
                        CurrencyFormatter.formatUnits(_feePaise),
                      ),
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total Payment',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            CurrencyFormatter.formatUnits(_totalPaise),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // Pay with UPI Button
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  onPressed: tripPayState.isProcessing
                      ? null
                      : _startContributionFlow,
                  label: tripPayState.isProcessing
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Pay ${CurrencyFormatter.formatUnits(_totalPaise)} with UPI',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                ),
              ),
              const SizedBox(height: AppConstants.spaceLg),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(ThemeData theme, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ],
    );
  }
}

/// Interactive UPI payment sheet supporting CREATED, WAITING, VERIFYING, SUCCESS, and FAILED states.
class _UpiPaymentSheet extends ConsumerStatefulWidget {
  final String tripId;
  final PaymentIntent intent;
  final VoidCallback onSuccess;
  final ValueChanged<String> onCancelOrFailed;

  const _UpiPaymentSheet({
    required this.tripId,
    required this.intent,
    required this.onSuccess,
    required this.onCancelOrFailed,
  });

  @override
  ConsumerState<_UpiPaymentSheet> createState() => _UpiPaymentSheetState();
}

enum _SheetState {
  waitingForPayment,
  verifyingPayment,
  success,
  failed,
  expired,
}

class _UpiPaymentSheetState extends ConsumerState<_UpiPaymentSheet> {
  _SheetState _state = _SheetState.waitingForPayment;
  String? _errorMessage;

  Future<void> _simulateUpiSuccess() async {
    setState(() => _state = _SheetState.verifyingPayment);

    final notifier = ref.read(tripPayProvider.notifier);
    final provider = notifier.paymentProvider;
    if (provider is SandboxPaymentProvider) {
      provider.simulatedStatus = PaymentStatus.success;
    }

    final attemptSnap = ref.read(tripPayProvider).paymentAttempts;
    final attemptId = attemptSnap.isNotEmpty
        ? attemptSnap.first.id
        : 'att_${widget.intent.id.hashCode.abs()}';

    final success = await notifier.verifyAndFinalizeContribution(
      tripId: widget.tripId,
      paymentAttemptId: attemptId,
      providerReference: 'upi_ref_${DateTime.now().millisecondsSinceEpoch}',
    );

    if (!mounted) return;

    if (success) {
      setState(() => _state = _SheetState.success);
      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted) widget.onSuccess();
    } else {
      setState(() {
        _state = _SheetState.failed;
        _errorMessage = 'Provider verification failed. Trip Pot unchanged.';
      });
    }
  }

  Future<void> _simulateUpiDecline() async {
    setState(() => _state = _SheetState.verifyingPayment);

    final notifier = ref.read(tripPayProvider.notifier);
    final provider = notifier.paymentProvider;
    if (provider is SandboxPaymentProvider) {
      provider.simulatedStatus = PaymentStatus.failed;
    }

    final attemptSnap = ref.read(tripPayProvider).paymentAttempts;
    final attemptId = attemptSnap.isNotEmpty
        ? attemptSnap.first.id
        : 'att_${widget.intent.id.hashCode.abs()}';

    await notifier.verifyAndFinalizeContribution(
      tripId: widget.tripId,
      paymentAttemptId: attemptId,
      providerReference:
          'declined_ref_${DateTime.now().millisecondsSinceEpoch}',
    );

    if (!mounted) return;

    setState(() {
      _state = _SheetState.failed;
      _errorMessage = 'Payment was declined or cancelled. Trip Pot unchanged.';
    });
  }

  void _simulateTimeout() {
    setState(() {
      _state = _SheetState.expired;
      _errorMessage = 'Payment request timed out. Please try again.';
    });
  }

  /// Polls the payment provider for updated status (Setu or external gateway).
  Future<void> _checkPaymentStatus() async {
    setState(() => _state = _SheetState.verifyingPayment);
    final notifier = ref.read(tripPayProvider.notifier);
    final status = await notifier.paymentProvider.fetchPaymentStatus(
      paymentIntentId: widget.intent.id,
      providerReference:
          widget.intent.metadata['platformBillID'] as String? ??
          widget.intent.id,
    );

    if (!mounted) return;

    if (status == PaymentStatus.success) {
      final attemptSnap = ref.read(tripPayProvider).paymentAttempts;
      final attemptId = attemptSnap.isNotEmpty
          ? attemptSnap.first.id
          : 'att_${widget.intent.id.hashCode.abs()}';

      final success = await notifier.verifyAndFinalizeContribution(
        tripId: widget.tripId,
        paymentAttemptId: attemptId,
        providerReference:
            widget.intent.metadata['platformBillID'] as String? ??
            widget.intent.id,
      );

      if (!mounted) return;
      if (success) {
        setState(() => _state = _SheetState.success);
        await Future.delayed(const Duration(milliseconds: 900));
        if (mounted) widget.onSuccess();
      } else {
        setState(() {
          _state = _SheetState.failed;
          _errorMessage = 'Provider verification failed. Trip Pot unchanged.';
        });
      }
    } else if (status == PaymentStatus.failed) {
      setState(() {
        _state = _SheetState.failed;
        _errorMessage = 'Payment was declined or failed at provider.';
      });
    } else if (status == PaymentStatus.expired) {
      setState(() {
        _state = _SheetState.expired;
        _errorMessage = 'Payment request has expired.';
      });
    } else {
      setState(() => _state = _SheetState.waitingForPayment);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Waiting for payment confirmation. Please complete in UPI app and refresh.',
          ),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSetuProvider = widget.intent.provider == 'setu';

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(AppConstants.spaceLg),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: AppConstants.spaceMd),

            if (_state == _SheetState.waitingForPayment) ...[
              Text(
                isSetuProvider ? 'UPI Test Payment' : 'Waiting for Payment',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Total: ${CurrencyFormatter.formatUnits(widget.intent.totalChargePaise)}',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: AppConstants.spaceMd),

              // UPI Details Container
              Container(
                padding: const EdgeInsets.all(AppConstants.spaceMd),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.qr_code_2,
                          size: 40,
                          color: Color(0xFF6366F1),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isSetuProvider
                                  ? 'Setu UPI UAT Intent'
                                  : 'UPI Intent / QR Simulation',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              isSetuProvider
                                  ? 'Sandbox / UAT Environment'
                                  : 'GPay • PhonePe • Paytm • BHIM',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (widget.intent.upiIntentUrl != null &&
                        widget.intent.upiIntentUrl!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SelectableText(
                          widget.intent.upiIntentUrl!,
                          style: const TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                          ),
                          maxLines: 2,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppConstants.spaceMd),
                    const Divider(),
                    const SizedBox(height: 8),

                    // Manual Status Refresh
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _checkPaymentStatus,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Refresh / Check Status'),
                      ),
                    ),

                    if (!isSetuProvider) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'SIMULATE PROVIDER OUTCOME (SANDBOX)',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1,
                          fontWeight: FontWeight.w800,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                              ),
                              onPressed: _simulateUpiSuccess,
                              icon: const Icon(Icons.check, size: 16),
                              label: const Text('Simulate Success'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red.shade700,
                              ),
                              onPressed: _simulateUpiDecline,
                              icon: const Icon(Icons.close, size: 16),
                              label: const Text('Decline'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _simulateTimeout,
                        child: const Text('Simulate Timeout / Expired'),
                      ),
                    ],
                  ],
                ),
              ),
            ] else if (_state == _SheetState.verifyingPayment) ...[
              const SizedBox(height: 20),
              const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 20),
              const Text(
                'Waiting for payment confirmation',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Verifying transaction with payment provider...',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
            ] else if (_state == _SheetState.success) ...[
              const SizedBox(height: 16),
              const Icon(
                Icons.check_circle,
                size: 64,
                color: Color(0xFF10B981),
              ),
              const SizedBox(height: 16),
              const Text(
                'Payment Confirmed • Money Added',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                '${CurrencyFormatter.formatUnits(widget.intent.amountPaise)} successfully credited to Trip Pot',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 20),
            ] else if (_state == _SheetState.failed ||
                _state == _SheetState.expired) ...[
              const SizedBox(height: 16),
              Icon(Icons.error_outline, size: 64, color: Colors.red.shade600),
              const SizedBox(height: 16),
              Text(
                _state == _SheetState.expired
                    ? 'Payment Expired'
                    : 'Payment Cancelled',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _errorMessage ?? 'Trip Pot balance remains unchanged.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => widget.onCancelOrFailed(
                    _errorMessage ?? 'Payment cancelled',
                  ),
                  child: const Text('Close'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
