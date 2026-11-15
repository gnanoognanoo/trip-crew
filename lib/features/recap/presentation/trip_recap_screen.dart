import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/core/services/analytics_service.dart';
import 'package:tripcrew/core/services/supabase_service.dart';
import 'package:tripcrew/core/utils/currency_formatter.dart';
import 'package:tripcrew/features/expenses/models/expense_model.dart';
import 'package:tripcrew/features/itinerary/models/itinerary_item.dart';
import 'package:tripcrew/features/memories/models/memory_model.dart';
import 'package:tripcrew/features/trips/providers/trips_provider.dart';

class TripRecapScreen extends ConsumerStatefulWidget {
  const TripRecapScreen({super.key});

  @override
  ConsumerState<TripRecapScreen> createState() => _TripRecapScreenState();
}

class _TripRecapScreenState extends ConsumerState<TripRecapScreen> {
  bool _isLoading = true;
  List<ExpenseModel> _expenses = [];
  List<ItineraryItem> _itinerary = [];
  List<MemoryModel> _memories = [];
  double? _calculatedDistanceKm;

  @override
  void initState() {
    super.initState();
    _loadRecapData();
  }

  Future<void> _loadRecapData() async {
    final activeTrip = ref.read(activeTripProvider);
    if (activeTrip == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    AnalyticsService.logRecapViewed(activeTrip.id);

    if (SupabaseService.isInitialized) {
      try {
        // 1. Fetch expenses
        final expRes = await SupabaseService.client
            .from('expenses')
            .select()
            .eq('trip_id', activeTrip.id);
        _expenses = (expRes as List)
            .map((e) => ExpenseModel.fromMap(
                  Map<String, dynamic>.from(e as Map),
                  e['id']?.toString() ?? '',
                ))
            .toList();

        // 2. Fetch itinerary
        final itinRes = await SupabaseService.client
            .from('itinerary_items')
            .select()
            .eq('trip_id', activeTrip.id)
            .order('order', ascending: true);
        _itinerary = (itinRes as List)
            .map((i) => ItineraryItem.fromMap(
                  Map<String, dynamic>.from(i as Map),
                  i['id']?.toString() ?? '',
                ))
            .toList();

        // 3. Fetch memories
        final memRes = await SupabaseService.client
            .from('memories')
            .select()
            .eq('trip_id', activeTrip.id)
            .order('created_at', ascending: true);
        _memories = (memRes as List)
            .map((m) => MemoryModel.fromMap(
                  Map<String, dynamic>.from(m as Map),
                  m['id']?.toString() ?? '',
                ))
            .toList();
      } catch (e) {
        developer.log('Error loading recap data from Supabase: $e', name: 'TripRecap');
      }
    }

    // Calculate real cumulative distance between coordinates if available
    _computeDistance();

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _computeDistance() {
    final coords = <List<double>>[];
    for (final item in _itinerary) {
      if (item.latitude != null && item.longitude != null) {
        coords.add([item.latitude!, item.longitude!]);
      }
    }

    if (coords.length >= 2) {
      double totalMeters = 0;
      for (int i = 0; i < coords.length - 1; i++) {
        totalMeters += Geolocator.distanceBetween(
          coords[i][0],
          coords[i][1],
          coords[i + 1][0],
          coords[i + 1][1],
        );
      }
      _calculatedDistanceKm = double.parse((totalMeters / 1000).toStringAsFixed(1));
    } else {
      _calculatedDistanceKm = null; // Do not invent fake distance!
    }
  }

  Future<void> _shareRecap() async {
    final activeTrip = ref.read(activeTripProvider);
    if (activeTrip == null) return;

    final totalSpendingPaise = _expenses.fold<int>(
      0,
      (sum, e) => sum + e.amountPaise,
    );
    final visitedCount = _itinerary.where((i) => i.isVisited).length;
    final distanceText = _calculatedDistanceKm != null
        ? '${_calculatedDistanceKm!} km mapped'
        : 'Journey highlights';

    final shareText = '''
✨ TripCrew Recap: ${activeTrip.name}
📍 ${activeTrip.startingPlace} → ${activeTrip.destination}
🗓️ ${activeTrip.durationDays} Days (${DateFormat('MMM d').format(activeTrip.startDate)} - ${DateFormat('MMM d, yyyy').format(activeTrip.endDate)})
👥 Crew Members: ${activeTrip.memberCount}

📊 Trip Highlights:
💰 Total Group Spending: ${CurrencyFormatter.formatUnits(totalSpendingPaise)}
🗺️ Itinerary Stops: $visitedCount / ${_itinerary.length} visited
📸 Shared Memories: ${_memories.length} captured moments
🚗 Distance: $distanceText

Planned and explored together with TripCrew!
''';

    try {
      await SharePlus.instance.share(
        ShareParams(
          text: shareText,
          subject: 'TripCrew Recap: ${activeTrip.name}',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share recap: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeTrip = ref.watch(activeTripProvider);

    if (activeTrip == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Trip Analytics & Story')),
        body: const Center(child: Text('No active trip selected.')),
      );
    }

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text('Recap: ${activeTrip.name}')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final totalSpendingPaise = _expenses.fold<int>(
      0,
      (sum, e) => sum + e.amountPaise,
    );
    final visitedCount = _itinerary.where((i) => i.isVisited).length;

    // Calculate category spending breakdown
    final Map<String, int> categoryTotals = {};
    for (final exp in _expenses) {
      final cat = exp.category.isNotEmpty ? exp.category : 'General';
      categoryTotals[cat] = (categoryTotals[cat] ?? 0) + exp.amountPaise;
    }

    final dateFormat = DateFormat('MMM d, yyyy');

    return Scaffold(
      appBar: AppBar(
        title: Text('Recap: ${activeTrip.name}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () { if (context.canPop()) { context.pop(); } else { context.go('/workspace'); } },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded),
            tooltip: 'Share Trip Recap',
            onPressed: _shareRecap,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppConstants.spaceSm),

              // Header Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppConstants.spaceLg),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(AppConstants.radiusXl),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4F46E5).withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${activeTrip.durationDays} Days Journey',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Text(
                          '${activeTrip.memberCount} Members',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      activeTrip.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${activeTrip.startingPlace} → ${activeTrip.destination}',
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${dateFormat.format(activeTrip.startDate)} - ${dateFormat.format(activeTrip.endDate)}',
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppConstants.spaceLg),

              // 2x2 Real Metrics Grid
              Row(
                children: [
                  Expanded(
                    child: _buildMetricCard(
                      context,
                      label: 'Total Spending',
                      value: CurrencyFormatter.formatUnits(totalSpendingPaise),
                      icon: Icons.account_balance_wallet_outlined,
                      color: const Color(0xFFF59E0B),
                    ),
                  ),
                  const SizedBox(width: AppConstants.spaceMd),
                  Expanded(
                    child: _buildMetricCard(
                      context,
                      label: 'Mapped Distance',
                      value: _calculatedDistanceKm != null
                          ? '${_calculatedDistanceKm!} km'
                          : '-- km',
                      icon: Icons.directions_car_rounded,
                      color: const Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppConstants.spaceMd),
              Row(
                children: [
                  Expanded(
                    child: _buildMetricCard(
                      context,
                      label: 'Stops Visited',
                      value: '$visitedCount / ${_itinerary.length}',
                      icon: Icons.place_outlined,
                      color: const Color(0xFF3B82F6),
                    ),
                  ),
                  const SizedBox(width: AppConstants.spaceMd),
                  Expanded(
                    child: _buildMetricCard(
                      context,
                      label: 'Memories Captured',
                      value: '${_memories.length}',
                      icon: Icons.photo_library_outlined,
                      color: const Color(0xFF8B5CF6),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppConstants.spaceXl),

              // Spending Category Breakdown
              Text(
                'Spending Breakdown',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppConstants.spaceSm),
              if (_expenses.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppConstants.spaceLg),
                    child: Center(
                      child: Text(
                        'No expenses recorded for this trip.',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                )
              else
                Card(
                  elevation: 1.5,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppConstants.spaceMd),
                    child: Column(
                      children: categoryTotals.entries.map((entry) {
                        final catName = entry.key;
                        final paise = entry.value;
                        final percent = totalSpendingPaise > 0
                            ? (paise / totalSpendingPaise)
                            : 0.0;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    catName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    '${CurrencyFormatter.formatUnits(paise)} (${(percent * 100).toStringAsFixed(0)}%)',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: percent,
                                  minHeight: 8,
                                  color: _getCategoryColor(catName),
                                  backgroundColor: Colors.grey.shade200,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),

              const SizedBox(height: AppConstants.spaceXl),

              // Trip Story Timeline (Itinerary Stops & Memories)
              Text(
                'Trip Timeline Highlights',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppConstants.spaceSm),
              if (_itinerary.isEmpty && _memories.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppConstants.spaceLg),
                    child: Center(
                      child: Text(
                        'No itinerary stops or memories logged yet.',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                )
              else
                Card(
                  elevation: 1.5,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppConstants.spaceMd),
                    child: Column(
                      children: _itinerary.map((stop) {
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: stop.isVisited
                                ? const Color(0xFF10B981)
                                : const Color(0xFF3B82F6),
                            child: Icon(
                              stop.isVisited
                                  ? Icons.check_circle_rounded
                                  : Icons.flag_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                          title: Text(
                            stop.title,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            'Day ${stop.dayNumber} • ${stop.time}${stop.placeName != null ? ' • ${stop.placeName}' : ''}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: stop.isVisited
                                  ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              stop.isVisited ? 'Completed' : 'Planned',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: stop.isVisited
                                    ? const Color(0xFF10B981)
                                    : Colors.grey.shade700,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),

              const SizedBox(height: AppConstants.spaceXl),

              // Share Button
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.share_rounded),
                  label: const Text('Share Trip Story with Crew'),
                  onPressed: _shareRecap,
                ),
              ),
              const SizedBox(height: AppConstants.space2xl),
            ],
          ),
        ),
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'food':
        return const Color(0xFFF59E0B);
      case 'travel':
      case 'fuel':
        return const Color(0xFF3B82F6);
      case 'stay':
      case 'hotel':
        return const Color(0xFF8B5CF6);
      case 'activities':
        return const Color(0xFFEC4899);
      default:
        return const Color(0xFF10B981);
    }
  }

  Widget _buildMetricCard(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
