import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/core/services/analytics_service.dart';
import 'package:tripcrew/core/services/firebase_service.dart';
import 'package:tripcrew/core/widgets/app_empty_state.dart';
import 'package:tripcrew/features/auth/providers/auth_provider.dart';
import 'package:tripcrew/features/memories/models/memory_model.dart';
import 'package:tripcrew/features/trips/providers/trips_provider.dart';

/// Screen 16: Shared Memories photo and video gallery connected to real Firestore trips/{tripId}/memories.
class SharedMemoriesScreen extends ConsumerStatefulWidget {
  const SharedMemoriesScreen({super.key});

  @override
  ConsumerState<SharedMemoriesScreen> createState() =>
      _SharedMemoriesScreenState();
}

class _SharedMemoriesScreenState extends ConsumerState<SharedMemoriesScreen> {
  int _selectedTab = 0; // 0: Photos, 1: Videos, 2: Timeline
  StreamSubscription? _sub;
  List<MemoryModel> _memories = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _listenToMemories();
  }

  void _listenToMemories() {
    final activeTrip = ref.read(activeTripProvider);
    if (activeTrip == null) {
      setState(() => _isLoading = false);
      return;
    }

    if (FirebaseService.isInitialized) {
      _sub = FirebaseFirestore.instance
          .collection('trips')
          .doc(activeTrip.id)
          .collection('memories')
          .orderBy('createdAt', descending: true)
          .snapshots()
          .listen(
            (snapshot) {
              final loaded = snapshot.docs
                  .map((doc) => MemoryModel.fromMap(doc.data(), doc.id))
                  .toList();

              if (mounted) {
                setState(() {
                  _memories = loaded;
                  _isLoading = false;
                });
              }
            },
            onError: (_) {
              if (mounted) setState(() => _isLoading = false);
            },
          );
    } else {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _showUploadDialog(String tripId) {
    final captionCtrl = TextEditingController();
    int dayNumber = 1;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
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
                  border: Border.all(color: Colors.blue.shade200),
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
                      'Select photo from device',
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
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: dayNumber,
                decoration: const InputDecoration(labelText: 'Day of Trip'),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('Day 1')),
                  DropdownMenuItem(value: 2, child: Text('Day 2')),
                  DropdownMenuItem(value: 3, child: Text('Day 3')),
                ],
                onChanged: (val) => setDialogState(() => dayNumber = val!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final user = ref.read(authProvider).user;
                final newMemory = MemoryModel(
                  id: 'm_${DateTime.now().millisecondsSinceEpoch}',
                  tripId: tripId,
                  uploaderId: user?.uid ?? 'guest',
                  photographerName: user?.name ?? 'Crew Member',
                  mediaUrl:
                      'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=800',
                  dayNumber: dayNumber,
                  caption: captionCtrl.text.trim().isNotEmpty
                      ? captionCtrl.text.trim()
                      : 'Unforgettable moments',
                  createdAt: DateTime.now(),
                );

                if (FirebaseService.isInitialized) {
                  await FirebaseFirestore.instance
                      .collection('trips')
                      .doc(tripId)
                      .collection('memories')
                      .doc(newMemory.id)
                      .set(newMemory.toMap());
                } else {
                  setState(() => _memories.insert(0, newMemory));
                }

                await AnalyticsService.logMemoryUploaded(tripId);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Upload'),
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

    if (activeTrip == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Shared Memories')),
        body: const Center(child: Text('No active trip selected.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shared Memories'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showUploadDialog(activeTrip.id),
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
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _memories.isEmpty
                  ? AppEmptyState(
                      icon: Icons.photo_library_outlined,
                      title: 'No shared memories yet',
                      message:
                          'Capture and upload photos with your crew during ${activeTrip.name}.',
                      actionLabel: 'Upload Photo',
                      onActionPressed: () => _showUploadDialog(activeTrip.id),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(AppConstants.spaceLg),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
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
                                title: Text(memory.caption ?? 'Trip Moment'),
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
                          borderRadius: BorderRadius.circular(
                            AppConstants.radiusLg,
                          ),
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
