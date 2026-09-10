import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tripcrew/core/constants/app_constants.dart';

class ExplorerPlace {
  final String name;
  final double rating;
  final double distanceKm;
  final String category;
  final String status;
  final IconData icon;

  const ExplorerPlace({
    required this.name,
    required this.rating,
    required this.distanceKm,
    required this.category,
    required this.status,
    required this.icon,
  });
}

/// Screen 13: Budget & Nearby Explorer screen matching UI design mockup.
class NearbyExplorerScreen extends ConsumerStatefulWidget {
  const NearbyExplorerScreen({super.key});

  @override
  ConsumerState<NearbyExplorerScreen> createState() =>
      _NearbyExplorerScreenState();
}

class _NearbyExplorerScreenState extends ConsumerState<NearbyExplorerScreen> {
  String _selectedCategory = 'Food';

  final List<ExplorerPlace> _places = const [
    ExplorerPlace(
      name: 'Baga Beach Shack',
      rating: 4.6,
      distanceKm: 0.5,
      category: 'Food',
      status: 'Open Now',
      icon: Icons.restaurant_rounded,
    ),
    ExplorerPlace(
      name: "Fisherman's Wharf",
      rating: 4.4,
      distanceKm: 1.2,
      category: 'Food',
      status: 'Closes 11 PM',
      icon: Icons.set_meal_rounded,
    ),
    ExplorerPlace(
      name: "Britto's Restaurant",
      rating: 4.3,
      distanceKm: 1.5,
      category: 'Food',
      status: 'Open Now',
      icon: Icons.local_dining_rounded,
    ),
    ExplorerPlace(
      name: 'Calangute Beach Spot',
      rating: 4.6,
      distanceKm: 2.0,
      category: 'Photo Spots',
      status: 'Public Access',
      icon: Icons.beach_access_rounded,
    ),
    ExplorerPlace(
      name: 'HP Fuel Station',
      rating: 4.2,
      distanceKm: 0.8,
      category: 'Fuel',
      status: 'Open 24/7',
      icon: Icons.local_gas_station_rounded,
    ),
    ExplorerPlace(
      name: 'Public Clean Restroom & Shower',
      rating: 4.1,
      distanceKm: 0.4,
      category: 'Restrooms',
      status: 'Free Access',
      icon: Icons.wc_rounded,
    ),
    ExplorerPlace(
      name: 'Taj Holiday Village Resort',
      rating: 4.8,
      distanceKm: 3.2,
      category: 'Hotels',
      status: '₹8,500/night',
      icon: Icons.hotel_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _places
        .where(
          (p) => p.category == _selectedCategory || _selectedCategory == 'All',
        )
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Explore Nearby'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spaceLg,
                vertical: 8,
              ),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search restaurants, cafes, fuel...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: const Icon(Icons.tune_rounded),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  fillColor: theme.colorScheme.surfaceContainerLow,
                ),
              ),
            ),

            // Development Places Preview Indicator
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spaceLg,
                vertical: 2,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFF59E0B)),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 14,
                      color: Color(0xFFB45309),
                    ),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Development Places Preview • Live Google Places API integration pending key.',
                        style: TextStyle(
                          fontSize: 10,
                          color: Color(0xFF92400E),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Category Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spaceLg,
                vertical: 6,
              ),
              child: Row(
                children: [
                  _buildCategoryChip('Food', Icons.restaurant_rounded),
                  const SizedBox(width: 8),
                  _buildCategoryChip('Hotels', Icons.hotel_rounded),
                  const SizedBox(width: 8),
                  _buildCategoryChip('Fuel', Icons.local_gas_station_rounded),
                  const SizedBox(width: 8),
                  _buildCategoryChip('Restrooms', Icons.wc_rounded),
                  const SizedBox(width: 8),
                  _buildCategoryChip('Photo Spots', Icons.camera_alt_rounded),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Discovered Places List
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spaceLg,
                ),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final place = filtered[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: AppConstants.spaceSm),
                    child: Padding(
                      padding: const EdgeInsets.all(AppConstants.spaceMd),
                      child: Row(
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer
                                  .withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(
                                AppConstants.radiusMd,
                              ),
                            ),
                            child: Icon(
                              place.icon,
                              color: theme.colorScheme.primary,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: AppConstants.spaceMd),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  place.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.star_rounded,
                                      size: 16,
                                      color: Colors.amber,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      '${place.rating}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '• ${place.distanceKm} km',
                                      style: TextStyle(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  place.status,
                                  style: TextStyle(
                                    color: place.status.contains('Open')
                                        ? const Color(0xFF10B981)
                                        : theme.colorScheme.secondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.directions_rounded),
                            color: theme.colorScheme.primary,
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Directions to ${place.name}'),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChip(String label, IconData icon) {
    final isSelected = _selectedCategory == label;
    final theme = Theme.of(context);

    return FilterChip(
      selected: isSelected,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: isSelected ? Colors.white : theme.colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
      onSelected: (_) => setState(() => _selectedCategory = label),
    );
  }
}
