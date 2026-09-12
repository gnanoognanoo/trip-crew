import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/features/trips/providers/trips_provider.dart';

/// Screen 4: Create a Trip matching the UI design specification.
class CreateTripScreen extends ConsumerStatefulWidget {
  const CreateTripScreen({super.key});

  @override
  ConsumerState<CreateTripScreen> createState() => _CreateTripScreenState();
}

class _CreateTripScreenState extends ConsumerState<CreateTripScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _startingPlaceController = TextEditingController();
  final _destinationController = TextEditingController();
  final _budgetController = TextEditingController();

  DateTime _startDate = DateTime.now().add(const Duration(days: 7));
  DateTime _endDate = DateTime.now().add(const Duration(days: 10));
  String _selectedTripType = 'Road Trip';
  String _selectedCurrency = 'INR (₹)';
  bool _isSubmitting = false;

  final List<String> _tripTypes = [
    'Road Trip',
    'Vacation',
    'Family',
    'Adventure',
    'Trek',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _startingPlaceController.dispose();
    _destinationController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_endDate.isBefore(_startDate)) {
            _endDate = _startDate.add(const Duration(days: 3));
          }
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _handleCreateTrip() async {
    if (_isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      final trip = await ref
          .read(tripsProvider.notifier)
          .createTrip(
            name: _nameController.text,
            startingPlace: _startingPlaceController.text,
            destination: _destinationController.text,
            startDate: _startDate,
            endDate: _endDate,
            tripType: _selectedTripType,
            budget: double.tryParse(_budgetController.text) ?? 20000.0,
            currency: _selectedCurrency,
          );

      if (mounted) {
        context.pushReplacement('/trip-created', extra: trip);
      }
    } catch (e) {
      if (mounted) {
        String friendlyMessage =
            "We couldn't create your trip. Please try again.";
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyMessage)));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create a Trip'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceLg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppConstants.spaceMd),

                // Trip Name
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Trip Name',
                    hintText: 'e.g. Goa Weekend',
                  ),
                  validator: (val) => val == null || val.trim().isEmpty
                      ? 'Trip name is required'
                      : null,
                ),
                const SizedBox(height: AppConstants.spaceMd),

                // Starting Place
                TextFormField(
                  controller: _startingPlaceController,
                  decoration: const InputDecoration(
                    labelText: 'Starting Place',
                    hintText: 'e.g. Chennai',
                  ),
                  validator: (val) => val == null || val.trim().isEmpty
                      ? 'Starting place is required'
                      : null,
                ),
                const SizedBox(height: AppConstants.spaceMd),

                // Destination
                TextFormField(
                  controller: _destinationController,
                  decoration: const InputDecoration(
                    labelText: 'Destination',
                    hintText: 'e.g. Goa',
                  ),
                  validator: (val) => val == null || val.trim().isEmpty
                      ? 'Destination is required'
                      : null,
                ),
                const SizedBox(height: AppConstants.spaceMd),

                // Dates Row
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _pickDate(isStart: true),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Start Date',
                            suffixIcon: Icon(Icons.calendar_today, size: 18),
                          ),
                          child: Text(
                            dateFormat.format(_startDate),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppConstants.spaceSm),
                    Expanded(
                      child: InkWell(
                        onTap: () => _pickDate(isStart: false),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'End Date',
                            suffixIcon: Icon(Icons.calendar_today, size: 18),
                          ),
                          child: Text(
                            dateFormat.format(_endDate),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppConstants.spaceLg),

                // Trip Type
                const Text(
                  'Trip Type',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: AppConstants.spaceSm),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _tripTypes.map((type) {
                    final isSelected = _selectedTripType == type;
                    return ChoiceChip(
                      label: Text(type),
                      selected: isSelected,
                      onSelected: (val) =>
                          setState(() => _selectedTripType = type),
                    );
                  }).toList(),
                ),
                const SizedBox(height: AppConstants.spaceLg),

                // Budget and Currency
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _budgetController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Budget',
                          hintText: '20000',
                        ),
                        validator: (val) => val == null || val.trim().isEmpty
                            ? 'Enter budget'
                            : null,
                      ),
                    ),
                    const SizedBox(width: AppConstants.spaceSm),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedCurrency,
                        decoration: const InputDecoration(
                          labelText: 'Currency',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'INR (₹)',
                            child: Text('INR (₹)'),
                          ),
                          DropdownMenuItem(
                            value: 'USD (\$)',
                            child: Text('USD (\$)'),
                          ),
                          DropdownMenuItem(
                            value: 'EUR (€)',
                            child: Text('EUR (€)'),
                          ),
                        ],
                        onChanged: (val) =>
                            setState(() => _selectedCurrency = val!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppConstants.space2xl),

                // Create Trip Button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isSubmitting ? null : _handleCreateTrip,
                    child: _isSubmitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Create Trip'),
                  ),
                ),
                const SizedBox(height: AppConstants.spaceLg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
