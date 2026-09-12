import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/core/services/analytics_service.dart';
import 'package:tripcrew/core/services/cloudinary_service.dart';
import 'package:tripcrew/core/services/firebase_service.dart';
import 'package:tripcrew/core/widgets/app_empty_state.dart';
import 'package:tripcrew/core/widgets/app_error_state.dart';
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
  String? _errorMessage;

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
      _sub?.cancel();
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
                  _errorMessage = null;
                });
              }
            },
            onError: (err) {
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _errorMessage =
                      'Network or access issue loading memories. Please check your connection.';
                });
              }
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
    Uint8List? selectedImageBytes;
    String? selectedFilename;
    bool isUploading = false;
    String? uploadError;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Shared Memory'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: isUploading
                      ? null
                      : () async {
                          try {
                            final picker = ImagePicker();
                            final picked = await picker.pickImage(
                              source: ImageSource.gallery,
                              maxWidth: 1920,
                              maxHeight: 1080,
                              imageQuality: 85,
                            );
                            if (picked != null) {
                              final bytes = await picked.readAsBytes();
                              setDialogState(() {
                                selectedImageBytes = bytes;
                                selectedFilename = picked.name;
                                uploadError = null;
                              });
                            }
                          } catch (e) {
                            setDialogState(() {
                              uploadError = 'Could not select image: $e';
                            });
                          }
                        },
                  child: Container(
                    height: 140,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: selectedImageBytes != null
                        ? Image.memory(selectedImageBytes!, fit: BoxFit.cover)
                        : const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.add_photo_alternate_rounded,
                                size: 36,
                                color: Colors.blue,
                              ),
                              SizedBox(height: 6),
                              Text(
                                'Tap to choose photo from device',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                if (uploadError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    uploadError!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: captionCtrl,
                  enabled: !isUploading,
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
                    DropdownMenuItem(value: 4, child: Text('Day 4')),
                    DropdownMenuItem(value: 5, child: Text('Day 5')),
                  ],
                  onChanged: isUploading
                      ? null
                      : (val) => setDialogState(() => dayNumber = val!),
                ),
                if (isUploading) ...[
                  const SizedBox(height: 16),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Uploading to Cloudinary...',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isUploading ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: isUploading
                  ? null
                  : () async {
                      final user = ref.read(authProvider).user;
                      if (user == null || user.uid.isEmpty) {
                        setDialogState(() {
                          uploadError =
                              'You must be signed in with Firebase to upload trip memories.';
                        });
                        return;
                      }

                      if (selectedImageBytes == null) {
                        setDialogState(() {
                          uploadError =
                              'Please tap the area above to select an image first.';
                        });
                        return;
                      }

                      setDialogState(() {
                        isUploading = true;
                        uploadError = null;
                      });

                      String? uploadedPublicId;
                      String? uploadedImageUrl;

                      try {
                        // 1. Upload to Cloudinary with validation & authorization guards
                        final uploadRes = await CloudinaryService.uploadMemory(
                          bytes: selectedImageBytes!,
                          filename:
                              selectedFilename ??
                              'memory_${DateTime.now().millisecondsSinceEpoch}.jpg',
                          tripId: tripId,
                          uid: user.uid,
                        );

                        uploadedPublicId = uploadRes.publicId;
                        uploadedImageUrl = uploadRes.secureUrl;

                        // 2. Prepare MemoryModel with Cloudinary metadata
                        final now = DateTime.now();
                        final newMemory = MemoryModel(
                          id: 'm_${now.millisecondsSinceEpoch}',
                          tripId: tripId,
                          uploaderId: user.uid,
                          photographerName: user.name,
                          imageUrl: uploadedImageUrl,
                          publicId: uploadedPublicId,
                          dayIndex: dayNumber,
                          caption: captionCtrl.text.trim().isNotEmpty
                              ? captionCtrl.text.trim()
                              : 'Unforgettable moments',
                          createdAt: now,
                          capturedAt: now,
                        );

                        // 3. Write metadata to Firestore
                        if (FirebaseService.isInitialized) {
                          try {
                            await FirebaseFirestore.instance
                                .collection('trips')
                                .doc(tripId)
                                .collection('memories')
                                .doc(newMemory.id)
                                .set(
                                  newMemory.toFirestoreMap(
                                    useServerTimestamp: true,
                                  ),
                                );
                          } catch (firestoreError) {
                            developer.log(
                              'ORPHAN_ASSET_ALERT: Cloudinary asset publicId=[$uploadedPublicId] '
                              'URL=[$uploadedImageUrl] was uploaded, but Firestore write failed for trip [$tripId]. '
                              'Asset is orphaned and should be cleaned up by backend service. Error: $firestoreError',
                              name: 'TripCrewMedia',
                              level: 1000,
                            );
                            throw Exception(
                              'Photo uploaded, but failed to save to the trip. Please try again.',
                            );
                          }
                        } else {
                          setState(() => _memories.insert(0, newMemory));
                        }

                        await AnalyticsService.logMemoryUploaded(tripId);
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        setDialogState(() {
                          isUploading = false;
                          if (e is CloudinaryValidationException) {
                            uploadError = e.message;
                          } else if (e is CloudinaryAuthException) {
                            uploadError = e.message;
                          } else if (e is CloudinaryUploadException) {
                            uploadError = e.message;
                          } else {
                            uploadError = e.toString().replaceFirst(
                              'Exception: ',
                              '',
                            );
                          }
                        });
                      }
                    },
              child: const Text('Upload'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteMemory(MemoryModel memory, String tripId) async {
    try {
      final user = ref.read(authProvider).user;
      if (FirebaseService.isInitialized) {
        // 1. Delete memory document from Firestore
        await FirebaseFirestore.instance
            .collection('trips')
            .doc(tripId)
            .collection('memories')
            .doc(memory.id)
            .delete();

        // 2. Queue for future backend Cloudinary remote deletion
        if (memory.publicId.isNotEmpty) {
          try {
            await FirebaseFirestore.instance
                .collection('mediaCleanupQueue')
                .add({
                  'publicId': memory.publicId,
                  'tripId': tripId,
                  'requestedBy': user?.uid ?? 'unknown',
                  'createdAt': FieldValue.serverTimestamp(),
                  'status': 'pending',
                  'imageUrl': memory.imageUrl,
                });
            developer.log(
              'MEDIA_CLEANUP_QUEUED: Enqueued publicId [${memory.publicId}] to mediaCleanupQueue',
              name: 'TripCrewMedia',
            );
          } catch (queueErr) {
            developer.log(
              'MEDIA_CLEANUP_QUEUE_WARN: Failed to enqueue [${memory.publicId}]: $queueErr',
              name: 'TripCrewMedia',
            );
          }
        }
      }

      setState(() {
        _memories.removeWhere((m) => m.id == memory.id);
      });

      developer.log(
        'FIRESTORE_METADATA_DELETED: Memory document [${memory.id}] deleted from Firestore. '
        'Notice: Remote Cloudinary asset [${memory.publicId}] was queued to mediaCleanupQueue.',
        name: 'TripCrewMedia',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Memory removed from trip. (Queued for remote media cleanup)',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete memory: $e'),
            backgroundColor: Colors.red,
          ),
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
                  : _errorMessage != null
                  ? AppErrorState(
                      title: 'Could Not Load Memories',
                      message: _errorMessage!,
                      onRetry: () {
                        setState(() {
                          _isLoading = true;
                          _errorMessage = null;
                        });
                        _listenToMemories();
                      },
                    )
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
                        final currentUser = ref.watch(authProvider).user;
                        final canDelete =
                            currentUser != null &&
                            (currentUser.uid == memory.uploaderId ||
                                currentUser.uid == activeTrip.ownerId);

                        return InkWell(
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: Text(memory.caption ?? 'Trip Moment'),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: memory.imageUrl.isNotEmpty
                                          ? Image.network(
                                              memory.imageUrl,
                                              height: 200,
                                              width: double.infinity,
                                              fit: BoxFit.cover,
                                              errorBuilder:
                                                  (
                                                    context,
                                                    error,
                                                    stackTrace,
                                                  ) => Container(
                                                    height: 180,
                                                    decoration: BoxDecoration(
                                                      gradient: LinearGradient(
                                                        colors: grad,
                                                      ),
                                                    ),
                                                    child: const Center(
                                                      child: Icon(
                                                        Icons.photo_rounded,
                                                        size: 64,
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                  ),
                                            )
                                          : Container(
                                              height: 180,
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: grad,
                                                ),
                                              ),
                                              child: const Center(
                                                child: Icon(
                                                  Icons.photo_rounded,
                                                  size: 64,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Captured by ${memory.photographerName} • Day ${memory.dayNumber}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                                actions: [
                                  if (canDelete)
                                    TextButton(
                                      onPressed: () async {
                                        Navigator.pop(ctx);
                                        await _deleteMemory(
                                          memory,
                                          activeTrip.id,
                                        );
                                      },
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.red,
                                      ),
                                      child: const Text('Delete'),
                                    ),
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
                            clipBehavior: Clip.antiAlias,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (memory.imageUrl.isNotEmpty)
                                  Image.network(
                                    memory.imageUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (
                                          context,
                                          error,
                                          stackTrace,
                                        ) => Container(
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: grad,
                                            ),
                                          ),
                                          child: const Center(
                                            child: Icon(
                                              Icons.photo_camera_back_rounded,
                                              color: Colors.white70,
                                              size: 48,
                                            ),
                                          ),
                                        ),
                                    loadingBuilder:
                                        (context, child, loadingProgress) {
                                          if (loadingProgress == null) {
                                            return child;
                                          }
                                          return Container(
                                            color: Colors.black12,
                                            child: const Center(
                                              child: SizedBox(
                                                width: 24,
                                                height: 24,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              ),
                                            ),
                                          );
                                        },
                                  )
                                else
                                  Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(colors: grad),
                                    ),
                                    child: const Center(
                                      child: Icon(
                                        Icons.photo_camera_back_rounded,
                                        color: Colors.white70,
                                        size: 48,
                                      ),
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
