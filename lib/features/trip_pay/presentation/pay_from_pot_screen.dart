import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/core/services/analytics_service.dart';
import 'package:tripcrew/core/services/firebase_service.dart';
import 'package:tripcrew/core/utils/currency_formatter.dart';
import 'package:tripcrew/features/auth/providers/auth_provider.dart';
import 'package:tripcrew/features/trip_pay/providers/trip_pay_notifier.dart';
import 'package:tripcrew/features/trips/providers/trips_provider.dart';

/// Screen for paying from the shared Trip Pot.
/// Streamlined fast payment flow with inline review and dedicated Success Screen.
class PayFromPotScreen extends ConsumerStatefulWidget {
  const PayFromPotScreen({super.key});

  @override
  ConsumerState<PayFromPotScreen> createState() => _PayFromPotScreenState();
}

class _PayFromPotScreenState extends ConsumerState<PayFromPotScreen> {
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _merchantController = TextEditingController();
  String _category = 'Food';
  String? _clientRequestId;

  // Track payment success state to render dedicated success screen
  bool _paymentSuccess = false;
  int _lastPaidAmountPaise = 0;
  String _lastPaidDescription = '';
  String _lastPaidTripName = '';
  String _lastPaidInitiator = '';
  int _remainingPotPaise = 0;

  static const _categories = [
    'Food',
    'Stay',
    'Fuel',
    'Travel',
    'Tickets',
    'Shopping',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _clientRequestId =
        'pay_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}';
    final activeTrip = ref.read(activeTripProvider);
    if (activeTrip != null) {
      AnalyticsService.logTripPotPaymentStarted(activeTrip.id);
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _merchantController.dispose();
    super.dispose();
  }

  int get _amountPaise {
    final amount = double.tryParse(_amountController.text) ?? 0;
    return CurrencyFormatter.toSmallestUnit(amount);
  }

  Future<void> _submitPayment() async {
    final amountPaise = _amountPaise;
    final description = _descriptionController.text.trim();
    final merchant = _merchantController.text.trim();

    if (amountPaise <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount.')),
      );
      return;
    }

    if (description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a description (e.g. Dinner, Fuel).'),
        ),
      );
      return;
    }

    if (!FirebaseService.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('TripCrew Pay requires an internet connection.'),
        ),
      );
      return;
    }

    final activeTrip = ref.read(activeTripProvider);
    if (activeTrip == null) return;

    final summary = ref.read(tripPayProvider).summary;
    final available = summary?.availableBalancePaise ?? 0;

    if (amountPaise > available) {
      AnalyticsService.logInsufficientBalanceShown(activeTrip.id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Insufficient Trip Pot balance.')),
      );
      return;
    }

    final currentUser = ref.read(authProvider).user;
    final initiatorName = currentUser?.name.isNotEmpty == true
        ? currentUser!.name
        : 'Crew Member';

    final success = await ref
        .read(tripPayProvider.notifier)
        .makePayment(
          tripId: activeTrip.id,
          amountPaise: amountPaise,
          description: description,
          category: _category,
          merchantName: merchant.isNotEmpty ? merchant : null,
          clientRequestId: _clientRequestId!,
        );

    if (mounted) {
      if (success) {
        AnalyticsService.logTripPotPaymentCompleted(activeTrip.id);
        setState(() {
          _paymentSuccess = true;
          _lastPaidAmountPaise = amountPaise;
          _lastPaidDescription = description;
          _lastPaidTripName = activeTrip.name;
          _lastPaidInitiator = initiatorName;
          _remainingPotPaise = available - amountPaise;
        });
      } else {
        _clientRequestId =
            'pay_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}';
        final error = ref.read(tripPayProvider).error;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error ?? 'Payment failed.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_paymentSuccess) {
      return _buildSuccessScreen();
    }

    final tripPayState = ref.watch(tripPayProvider);
    final activeTrip = ref.watch(activeTripProvider);
    final currentUser = ref.watch(authProvider).user;
    final available = tripPayState.summary?.availableBalancePaise ?? 0;
    final initiatorName = currentUser?.name.isNotEmpty == true
        ? currentUser!.name
        : 'Crew Member';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pay from Trip Pot'),
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

              // Sandbox Banner
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
                        'SANDBOX • No real money is transferred.',
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
              const SizedBox(height: AppConstants.spaceMd),

              // Available Balance Card
              Card(
                color: const Color(0xFF0F4C81),
                child: Padding(
                  padding: const EdgeInsets.all(AppConstants.spaceMd),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Trip Pot Balance',
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                          if (activeTrip != null)
                            Text(
                              activeTrip.name,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                      Text(
                        CurrencyFormatter.formatUnits(available),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spaceMd),

              // Inputs
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                enabled: !tripPayState.isProcessing,
                decoration: const InputDecoration(
                  labelText: 'Amount (₹)',
                  prefixText: '₹ ',
                  border: OutlineInputBorder(),
                  hintText: 'e.g. 1200',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppConstants.spaceMd),

              TextField(
                controller: _descriptionController,
                enabled: !tripPayState.isProcessing,
                decoration: const InputDecoration(
                  labelText: 'What is this for?',
                  hintText: 'e.g. Dinner, Fuel, Tickets',
                  prefixIcon: Icon(Icons.description_rounded),
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppConstants.spaceMd),

              TextField(
                controller: _merchantController,
                enabled: !tripPayState.isProcessing,
                decoration: const InputDecoration(
                  labelText: 'Merchant / Place (optional)',
                  hintText: 'e.g. Beach Shack, Highway Petrol Bunk',
                  prefixIcon: Icon(Icons.store_rounded),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppConstants.spaceMd),

              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  prefixIcon: Icon(Icons.category_rounded),
                  border: OutlineInputBorder(),
                ),
                items: _categories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: tripPayState.isProcessing
                    ? null
                    : (val) => setState(() => _category = val!),
              ),
              const SizedBox(height: AppConstants.spaceLg),

              // Review Section
              Container(
                padding: const EdgeInsets.all(AppConstants.spaceMd),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PAYMENT REVIEW',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _reviewRow(
                      'Amount',
                      CurrencyFormatter.formatUnits(_amountPaise),
                    ),
                    _reviewRow(
                      'Available balance',
                      CurrencyFormatter.formatUnits(available),
                    ),
                    _reviewRow('Initiated by', initiatorName),
                  ],
                ),
              ),
              const SizedBox(height: AppConstants.spaceLg),

              // Confirm Sandbox Payment Button
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: tripPayState.isProcessing ? null : _submitPayment,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: tripPayState.isProcessing
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Confirm Sandbox Payment',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: AppConstants.space2xl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  /// Dedicated Success Screen matching Item 6 specification:
  /// Payment Recorded ✓
  /// ₹1,200
  /// Dinner
  /// Paid from Goa Trip Pot
  /// Initiated by: Account A
  /// Remaining Trip Pot: ₹18,800
  /// [Done]
  Widget _buildSuccessScreen() {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spaceXl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),

              // Success Icon
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Color(0xFFDCFCE7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Color(0xFF10B981),
                  size: 56,
                ),
              ),
              const SizedBox(height: AppConstants.spaceLg),

              const Text(
                'Payment Recorded ✓',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF10B981),
                ),
              ),
              const SizedBox(height: AppConstants.spaceMd),

              Text(
                CurrencyFormatter.formatUnits(_lastPaidAmountPaise),
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),

              Text(
                _lastPaidDescription,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),

              Text(
                'Paid from $_lastPaidTripName Pot',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Initiated by:',
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                        Text(
                          _lastPaidInitiator,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Remaining Trip Pot:',
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                        Text(
                          CurrencyFormatter.formatUnits(_remainingPotPaise),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F4C81),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppConstants.spaceMd),

              // Sandbox note
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'SANDBOX MODE • Simulated group payment. No real money was moved.',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF92400E),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              const Spacer(),

              // Done Button
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => context.pop(),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spaceMd),
            ],
          ),
        ),
      ),
    );
  }
}
