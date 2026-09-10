import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/core/services/analytics_service.dart';
import 'package:tripcrew/features/memories/models/memory_model.dart';

/// Screen 16: Shared Memories photo and video gallery matching UI design mockup.
class SharedMemoriesScreen extends ConsumerStatefulWidget {
  const SharedMemoriesScreen({super.key});

  @override
  ConsumerState<SharedMemoriesScreen> createState() =>
      _SharedMemoriesScreenState();
}

class _SharedMemoriesScreenState extends ConsumerState<SharedMemoriesScreen> {
  int _selectedTab = 0; // 0: Photos, 1: Videos, 2: Timeline

  final List<MemoryModel> _memories = [
    MemoryModel(
      id: 'm1',
      tripId: 'trip_goa_01',
      uploaderId: 'demo_kowshik_101',
      photographerName: 'Kowshik',
      mediaUrl: 'beach_sunset',
      dayNumber: 1,
      caption: 'Sunset at Anjuna Clifftop with the crew',
      createdAt: DateTime(2024, 10, 15, 18, 45),
    ),
    MemoryModel(
      id: 'm2',
      tripId: 'trip_goa_01',
      uploaderId: 'user_arun_102',
      photographerName: 'Arun',
      mediaUrl: 'coastal_ocean',
      dayNumber: 1,
      caption: 'Clear blue waves at Baga Beach',
      createdAt: DateTime(2024, 10, 15, 15, 30),
    ),
    MemoryModel(
      id: 'm3',
      tripId: 'trip_goa_01',
      uploaderId: 'user_rahul_103',
      photographerName: 'Rahul',
      mediaUrl: 'crew_cliff',
      dayNumber: 2,
      caption: 'All 4 of us reaching Chapora Fort',
      createdAt: DateTime(2024, 10, 16, 11, 20),
    ),
    MemoryModel(
      id: 'm4',
      tripId: 'trip_goa_01',
      uploaderId: 'user_praveen_104',
      photographerName: 'Praveen',
      mediaUrl: 'dinner_feast',
      dayNumber: 2,
      caption: 'Goan fish curry and seafood feast',
      createdAt: DateTime(2024, 10, 16, 20, 10),
    ),
  ];

  void _showUploadDialog() {
    final captionCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Shared Memory'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 120,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.blue.shade200,
                  style: BorderStyle.solid,
                ),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_photo_alternate_rounded,
                    size: 36,
                    color: Colors.blue,
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Select photo from gallery',
                    style: TextStyle(fontSize: 12, color: Colors.blue),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: captionCtrl,
              decoration: const InputDecoration(
                labelText: 'Memory Caption (optional)',
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
              setState(() {
                _memories.insert(
                  0,
                  MemoryModel(
                    id: 'm_${DateTime.now().millisecondsSinceEpoch}',
                    tripId: 'trip_goa_01',
                    uploaderId: 'demo_kowshik_101',
                    photographerName: 'Kowshik',
                    mediaUrl: 'new_memory',
                    dayNumber: 2,
                    caption: captionCtrl.text.trim().isNotEmpty
                        ? captionCtrl.text.trim()
                        : 'Unforgettable Goa vibes',
                    createdAt: DateTime.now(),
                  ),
                );
              });
              AnalyticsService.logMemoryUploaded('trip_goa_01');
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Memory shared with the crew!')),
              );
            },
            child: const Text('Upload'),
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
        title: const Text('Shared Memories'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showUploadDialog,
        backgroundColor: theme.colorScheme.primary,
        child: const Icon(Icons.add_a_photo_rounded, color: Colors.white),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Tabs: Photos, Videos, Timeline
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spaceLg,
                vertical: 8,
              ),
              child: Row(
                children: [
                  _buildTab('Photos', 0),
                  const SizedBox(width: AppConstants.spaceSm),
                  _buildTab('Videos', 1),
                  const SizedBox(width: AppConstants.spaceSm),
                  _buildTab('Timeline', 2),
                ],
              ),
            ),

            // Gallery Grid
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(AppConstants.spaceLg),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.85,
                ),
                itemCount: _memories.length,
                itemBuilder: (context, index) {
                  final memory = _memories[index];
                  final gradients = [
                    const [Color(0xFF1E3C72), Color(0xFF2A5298)],
                    const [Color(0xFFE65C00), Color(0xFFF9D423)],
                    const [Color(0xFF11998E), Color(0xFF38EF7D)],
                    const [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
                  ];
                  final grad = gradients[index % gradients.length];

                  return InkWell(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(memory.caption ?? 'Goa Memory'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                height: 180,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: grad),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.photo_rounded,
                                    size: 64,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Captured by ${memory.photographerName} on Day ${memory.dayNumber}',
                              ),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: grad,
                        ),
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusLg,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          const Center(
                            child: Icon(
                              Icons.photo_camera_back_rounded,
                              color: Colors.white70,
                              size: 48,
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                    Colors.black.withValues(alpha: 0.8),
                                    Colors.transparent,
                                  ],
                                ),
                                borderRadius: const BorderRadius.only(
                                  bottomLeft: Radius.circular(
                                    AppConstants.radiusLg,
                                  ),
                                  bottomRight: Radius.circular(
                                    AppConstants.radiusLg,
                                  ),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    memory.caption ?? 'Trip Moment',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    'by ${memory.photographerName} • Day ${memory.dayNumber}',
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.8,
                                      ),
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
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
        ),
      ),
    );
  }

  Widget _buildTab(String label, int index) {
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
