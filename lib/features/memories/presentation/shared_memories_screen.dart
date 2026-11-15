import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/core/services/analytics_service.dart';
import 'package:tripcrew/core/services/supabase_service.dart';
import 'package:tripcrew/core/widgets/app_empty_state.dart';
import 'package:tripcrew/core/widgets/app_error_state.dart';
import 'package:tripcrew/features/auth/providers/auth_provider.dart';
import 'package:tripcrew/features/memories/models/memory_model.dart';
import 'package:tripcrew/features/trips/providers/trips_provider.dart';

/// Screen 16: Shared Memories photo and video gallery connected to Supabase PostgreSQL memories table
/// and Supabase Storage bucket 'trip-memories' (with Cloudinary fallback).
class SharedMemoriesScreen extends ConsumerStatefulWidget {
  const SharedMemoriesScreen({super.key});

  @override
  ConsumerState<SharedMemoriesScreen> createState() =>
      _SharedMemoriesScreenState();
}

class _SharedMemoriesScreenState extends ConsumerState<SharedMemoriesScreen> {
  int _selectedTab = 0; // 0: Photos, 1: Videos, 2: Timeline
  int? _filterDay; // null for All Days, or 1, 2, 3...
  List<MemoryModel> _memories = [];
  bool _isLoading = true;
  String? _errorMessage;
  StreamSubscription? _memoriesSub;

  @override
  void initState() {
    super.initState();
    _listenToMemories();
  }

  @override
  void dispose() {
    _memoriesSub?.cancel();
    super.dispose();
  }

  Future<void> _loadLocalMemories(String tripId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList('trip_memories_$tripId') ?? [];
      if (rawList.isNotEmpty) {
        final localList = rawList
            .map((item) {
              try {
                final map = jsonDecode(item) as Map<String, dynamic>;
                return MemoryModel.fromMap(map, map['id']?.toString() ?? '');
              } catch (_) {
                return null;
              }
            })
            .whereType<MemoryModel>()
            .toList();

        if (mounted && localList.isNotEmpty) {
          setState(() {
            _memories = _mergeMemories(_memories, localList);
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      developer.log('Error reading local memories: $e', name: 'SharedMemories');
    }
  }

  Future<void> _persistMemoriesLocally(String tripId, List<MemoryModel> memories) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = memories.map((m) => jsonEncode(m.toMap())).toList();
      await prefs.setStringList('trip_memories_$tripId', rawList);
    } catch (e) {
      developer.log('Error persisting local memories: $e', name: 'SharedMemories');
    }
  }

  List<MemoryModel> _mergeMemories(List<MemoryModel> current, List<MemoryModel> incoming) {
    final Map<String, MemoryModel> map = {};
    for (final m in incoming) {
      map[m.id] = m;
    }
    for (final m in current) {
      map[m.id] = m;
    }
    final list = map.values.toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Future<void> _listenToMemories() async {
    final activeTrip = ref.read(activeTripProvider);
    if (activeTrip == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    // 1. Immediately hydrate local persistent memories so media never disappears
    await _loadLocalMemories(activeTrip.id);
    if (_memories.isNotEmpty && mounted) {
      setState(() => _isLoading = false);
    }

    if (SupabaseService.isInitialized) {
      try {
        _memoriesSub?.cancel();
        _memoriesSub = SupabaseService.client
            .from('memories')
            .stream(primaryKey: ['id'])
            .eq('trip_id', activeTrip.id)
            .order('created_at', ascending: false)
            .listen(
              (data) {
                final loaded = data
                    .map((doc) => MemoryModel.fromMap(
                          Map<String, dynamic>.from(doc),
                          doc['id']?.toString() ?? '',
                        ))
                    .toList();
                if (mounted) {
                  setState(() {
                    _memories = _mergeMemories(loaded, _memories);
                    _isLoading = false;
                    _errorMessage = null;
                  });
                  _persistMemoriesLocally(activeTrip.id, _memories);
                }
              },
              onError: (err) async {
                try {
                  final res = await SupabaseService.client
                      .from('memories')
                      .select()
                      .eq('trip_id', activeTrip.id)
                      .order('created_at', ascending: false);

                  final loaded = (res as List)
                      .map((doc) => MemoryModel.fromMap(
                            Map<String, dynamic>.from(doc as Map),
                            doc['id']?.toString() ?? '',
                          ))
                      .toList();

                  if (mounted) {
                    setState(() {
                      _memories = _mergeMemories(loaded, _memories);
                      _isLoading = false;
                      _errorMessage = null;
                    });
                    _persistMemoriesLocally(activeTrip.id, _memories);
                  }
                } catch (e) {
                  developer.log('Error loading memories: $e', name: 'SharedMemories');
                  if (mounted) {
                    setState(() {
                      _isLoading = false;
                      if (_memories.isEmpty) {
                        _errorMessage =
                            'Could not load trip memories from database. Please check your connection.';
                      }
                    });
                  }
                }
              },
            );
      } catch (err) {
        developer.log('Error subscribing to memories: $err', name: 'SharedMemories');
        if (mounted) {
          setState(() {
            _isLoading = false;
            if (_memories.isEmpty) {
              _errorMessage =
                  'Could not load trip memories from database. Please check your connection.';
            }
          });
        }
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showUploadDialog(String tripId, int tripDurationDays) {
    final captionCtrl = TextEditingController();
    int dayNumber = 1;
    Uint8List? selectedBytes;
    String? selectedFilename;
    String mediaType = 'photo';
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ChoiceChip(
                      label: const Text('Photo'),
                      selected: mediaType == 'photo',
                      onSelected: isUploading
                          ? null
                          : (selected) {
                              if (selected) {
                                setDialogState(() {
                                  mediaType = 'photo';
                                  selectedBytes = null;
                                  selectedFilename = null;
                                  uploadError = null;
                                });
                              }
                            },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Video'),
                      selected: mediaType == 'video',
                      onSelected: isUploading
                          ? null
                          : (selected) {
                              if (selected) {
                                setDialogState(() {
                                  mediaType = 'video';
                                  selectedBytes = null;
                                  selectedFilename = null;
                                  uploadError = null;
                                });
                              }
                            },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: isUploading
                      ? null
                      : () async {
                          try {
                            final picker = ImagePicker();
                            XFile? picked;
                            if (mediaType == 'video') {
                              picked = await picker.pickVideo(
                                source: ImageSource.gallery,
                                maxDuration: const Duration(minutes: 3),
                              );
                            } else {
                              picked = await picker.pickImage(
                                source: ImageSource.gallery,
                                maxWidth: 1920,
                                maxHeight: 1080,
                                imageQuality: 85,
                              );
                            }

                            if (picked != null) {
                              final bytes = await picked.readAsBytes();
                              // Validate file size: 20MB for photo, 40MB for video
                              final maxBytes = mediaType == 'video'
                                  ? 40 * 1024 * 1024
                                  : 20 * 1024 * 1024;
                              if (bytes.lengthInBytes > maxBytes) {
                                setDialogState(() {
                                  uploadError =
                                      'File is too large. Maximum size is ${mediaType == 'video' ? '40MB' : '20MB'}.';
                                });
                                return;
                              }

                              setDialogState(() {
                                selectedBytes = bytes;
                                selectedFilename = picked!.name;
                                uploadError = null;
                              });
                            }
                          } catch (e) {
                            setDialogState(() {
                              uploadError = 'Could not select media: $e';
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
                    child: selectedBytes != null
                        ? (mediaType == 'video'
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.videocam_rounded,
                                    size: 48,
                                    color: Colors.blue,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    selectedFilename ?? 'Video selected',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              )
                            : Image.memory(selectedBytes!, fit: BoxFit.cover))
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                mediaType == 'video'
                                    ? Icons.video_call_rounded
                                    : Icons.add_photo_alternate_rounded,
                                size: 36,
                                color: Colors.blue,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                mediaType == 'video'
                                    ? 'Tap to select video (up to 40MB)'
                                    : 'Tap to choose photo from device',
                                style: const TextStyle(
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
                    labelText: 'Caption (optional)',
                    hintText: 'e.g. Sunset at the viewpoint',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: dayNumber,
                  decoration: const InputDecoration(labelText: 'Trip Day'),
                  items: List.generate(
                    tripDurationDays.clamp(1, 30),
                    (i) => DropdownMenuItem(
                      value: i + 1,
                      child: Text('Day ${i + 1}'),
                    ),
                  ),
                  onChanged: isUploading
                      ? null
                      : (val) {
                          if (val != null) {
                            setDialogState(() => dayNumber = val);
                          }
                        },
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
                        'Uploading to storage bucket...',
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
                              'You must be signed in to upload trip memories.';
                        });
                        return;
                      }

                      if (selectedBytes == null) {
                        setDialogState(() {
                          uploadError = 'Please select a file first.';
                        });
                        return;
                      }

                      setDialogState(() {
                        isUploading = true;
                        uploadError = null;
                      });

                      String uploadedUrl = '';
                      String? uploadedPublicId;
                      String? storagePath;

                      try {
                        final ext = selectedFilename?.split('.').last.toLowerCase() ??
                            (mediaType == 'video' ? 'mp4' : 'jpg');
                        final filename =
                            '${DateTime.now().millisecondsSinceEpoch}_${user.uid}.$ext';
                        storagePath = '$tripId/$filename';

                        // 1. Save locally to app persistent documents directory
                        final appDocs = await getApplicationDocumentsDirectory();
                        final memoriesDir = Directory('${appDocs.path}/memories/$tripId');
                        if (!memoriesDir.existsSync()) {
                          memoriesDir.createSync(recursive: true);
                        }
                        final localFilePath = '${memoriesDir.path}/$filename';
                        final localFile = File(localFilePath);
                        await localFile.writeAsBytes(selectedBytes!, flush: true);
                        uploadedUrl = localFilePath;

                        // 2. Attempt remote cloud upload
                        if (SupabaseService.isInitialized) {
                          try {
                            await SupabaseService.client.storage
                                .from('trip-memories')
                                .uploadBinary(
                                  storagePath,
                                  selectedBytes!,
                                  fileOptions: FileOptions(
                                    contentType: mediaType == 'video'
                                        ? 'video/$ext'
                                        : 'image/$ext',
                                    upsert: true,
                                  ),
                                );
                            uploadedUrl = SupabaseService.client.storage
                                .from('trip-memories')
                                .getPublicUrl(storagePath);
                          } catch (storageErr) {
                            developer.log(
                              'Supabase Storage upload fallback to persistent local file: $storageErr',
                              name: 'SharedMemories',
                            );
                            uploadedUrl = localFilePath;
                          }
                        }

                        final now = DateTime.now();
                        final newMemory = MemoryModel(
                          id: 'm_${now.millisecondsSinceEpoch}',
                          tripId: tripId,
                          uploaderId: user.uid,
                          photographerName: user.name.isNotEmpty
                              ? user.name
                              : 'Crew Member',
                          imageUrl: uploadedUrl,
                          publicId: uploadedPublicId ?? '',
                          storagePath: storagePath,
                          mediaType: mediaType,
                          dayIndex: dayNumber,
                          caption: captionCtrl.text.trim().isNotEmpty
                              ? captionCtrl.text.trim()
                              : (mediaType == 'video'
                                  ? 'Crew Video'
                                  : 'Trip Moment'),
                          createdAt: now,
                          capturedAt: now,
                        );

                        if (mounted) {
                          setState(() => _memories.insert(0, newMemory));
                        }

                        // Persist to local storage immediately
                        await _persistMemoriesLocally(tripId, _memories);

                        if (SupabaseService.isInitialized) {
                          try {
                            await SupabaseService.client
                                .from('memories')
                                .insert({
                              'id': newMemory.id,
                              'trip_id': tripId,
                              'user_id': user.uid,
                              'media_url': uploadedUrl.startsWith('http')
                                  ? uploadedUrl
                                  : 'local://$filename',
                              'caption': newMemory.caption,
                              'media_type': mediaType,
                              'cloudinary_public_id': uploadedPublicId,
                              'storage_path': storagePath,
                              'day_index': dayNumber,
                              'created_at': now.toIso8601String(),
                            });
                          } catch (dbErr) {
                            developer.log(
                              'Supabase memories table insert fallback: $dbErr',
                              name: 'SharedMemories',
                            );
                          }
                        }

                        await AnalyticsService.logMemoryUploaded(tripId);
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        setDialogState(() {
                          isUploading = false;
                          uploadError = e.toString().replaceFirst(
                                'Exception: ',
                                '',
                              );
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

  Future<void> _deleteMemory(MemoryModel memory) async {
    final activeTrip = ref.read(activeTripProvider);
    final currentUser = ref.read(authProvider).user;
    if (activeTrip == null || currentUser == null) return;

    final isOwner = currentUser.uid == activeTrip.ownerId;
    final isUploader = currentUser.uid == memory.uploaderId;

    if (!isOwner && !isUploader) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only the uploader or trip owner can delete this memory.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Memory?'),
        content: const Text(
          'This will permanently remove this item from the trip gallery for all members.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      if (SupabaseService.isInitialized) {
        await SupabaseService.client
            .from('memories')
            .delete()
            .eq('id', memory.id);

        if (memory.storagePath != null && memory.storagePath!.isNotEmpty) {
          try {
            await SupabaseService.client.storage
                .from('trip-memories')
                .remove([memory.storagePath!]);
          } catch (_) {}
        }
      }

      setState(() {
        _memories.removeWhere((m) => m.id == memory.id);
      });
      await _persistMemoriesLocally(activeTrip.id, _memories);
      if (memory.imageUrl.isNotEmpty && !memory.imageUrl.startsWith('http')) {
        try {
          final f = File(memory.imageUrl);
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Memory removed.')),
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

  List<MemoryModel> _getFilteredMemories() {
    return _memories.where((m) {
      if (_selectedTab == 0 && m.mediaType == 'video') return false;
      if (_selectedTab == 1 && m.mediaType != 'video') return false;
      if (_filterDay != null && m.dayIndex != _filterDay) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeTrip = ref.watch(activeTripProvider);
    final currentUser = ref.watch(authProvider).user;

    if (activeTrip == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Shared Memories')),
        body: const Center(child: Text('No active trip selected.')),
      );
    }

    final filtered = _getFilteredMemories();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/workspace');
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Shared Memories'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/workspace');
              }
            },
          ),
        actions: [
          // Filter by day menu
          PopupMenuButton<int?>(
            icon: const Icon(Icons.filter_list_rounded),
            tooltip: 'Filter by Day',
            onSelected: (day) => setState(() => _filterDay = day),
            itemBuilder: (context) => [
              const PopupMenuItem<int?>(
                value: null,
                child: Text('All Days'),
              ),
              ...List.generate(
                activeTrip.durationDays.clamp(1, 14),
                (i) => PopupMenuItem<int?>(
                  value: i + 1,
                  child: Text('Day ${i + 1}'),
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showUploadDialog(activeTrip.id, activeTrip.durationDays),
        backgroundColor: theme.colorScheme.primary,
        child: const Icon(Icons.add_a_photo_rounded, color: Colors.white),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Tabs: Photos / Videos / Timeline
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
                  const Spacer(),
                  if (_filterDay != null)
                    Chip(
                      label: Text('Day $_filterDay'),
                      onDeleted: () => setState(() => _filterDay = null),
                      deleteIconColor: theme.colorScheme.primary,
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ),

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
                      : filtered.isEmpty
                          ? AppEmptyState(
                              icon: Icons.photo_library_outlined,
                              title: _selectedTab == 1
                                  ? 'No shared videos yet'
                                  : 'No shared memories yet',
                              message:
                                  'Capture and share photos & videos with your crew during ${activeTrip.name}.',
                              actionLabel: 'Upload Media',
                              onActionPressed: () => _showUploadDialog(
                                activeTrip.id,
                                activeTrip.durationDays,
                              ),
                            )
                          : _selectedTab == 2
                              ? _buildTimelineView(filtered, currentUser?.uid, activeTrip.ownerId)
                              : _buildGridView(filtered, currentUser?.uid, activeTrip.ownerId),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildGridView(
    List<MemoryModel> memories,
    String? currentUid,
    String tripOwnerId,
  ) {
    return GridView.builder(
      padding: const EdgeInsets.all(AppConstants.spaceLg),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: memories.length,
      itemBuilder: (context, index) {
        final memory = memories[index];
        final canDelete = currentUid != null &&
            (currentUid == memory.uploaderId || currentUid == tripOwnerId);

        return _buildMemoryCard(memory, canDelete);
      },
    );
  }

  Widget _buildTimelineView(
    List<MemoryModel> memories,
    String? currentUid,
    String tripOwnerId,
  ) {
    // Group memories by dayIndex
    final Map<int, List<MemoryModel>> grouped = {};
    for (final m in memories) {
      grouped.putIfAbsent(m.dayIndex, () => []).add(m);
    }
    final sortedDays = grouped.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spaceLg,
        vertical: 8,
      ),
      itemCount: sortedDays.length,
      itemBuilder: (context, dayIdx) {
        final day = sortedDays[dayIdx];
        final dayMemories = grouped[day]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Day $day',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF8B5CF6),
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${dayMemories.length} item${dayMemories.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.85,
              ),
              itemCount: dayMemories.length,
              itemBuilder: (ctx, i) {
                final mem = dayMemories[i];
                final canDelete = currentUid != null &&
                    (currentUid == mem.uploaderId || currentUid == tripOwnerId);
                return _buildMemoryCard(mem, canDelete);
              },
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Widget _buildMemoryCard(MemoryModel memory, bool canDelete) {
    const gradients = [
      [Color(0xFF1E3C72), Color(0xFF2A5298)],
      [Color(0xFFE65C00), Color(0xFFF9D423)],
      [Color(0xFF11998E), Color(0xFF38EF7D)],
      [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
    ];
    final grad = gradients[memory.dayIndex % gradients.length];

    return InkWell(
      onTap: () => _showMemoryDetailDialog(memory, canDelete, grad),
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
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
            if (memory.mediaType == 'video')
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                  ),
                ),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.play_circle_fill_rounded,
                        color: Color(0xFF38BDF8),
                        size: 52,
                      ),
                      SizedBox(height: 6),
                      Text(
                        'VIDEO',
                        style: TextStyle(
                          color: Color(0xFF38BDF8),
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (memory.imageUrl.isNotEmpty)
              _buildMemoryImage(
                memory.imageUrl,
                fit: BoxFit.cover,
                placeholder: Container(
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

            // Video indicator badge
            if (memory.mediaType == 'video')
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),

            // Bottom gradient overlay with metadata
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
                        color: Colors.white.withValues(alpha: 0.8),
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
  }

  void _showMemoryDetailDialog(
    MemoryModel memory,
    bool canDelete,
    List<Color> grad,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(memory.caption ?? 'Trip Moment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (memory.mediaType == 'video')
              InkWell(
                onTap: () => _playVideo(memory.imageUrl),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  height: 200,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                    ),
                    border: Border.all(
                      color: const Color(0xFF38BDF8),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF38BDF8).withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          size: 54,
                          color: Color(0xFF38BDF8),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Tap to Play Video',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Opens in full screen video player',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: memory.imageUrl.isNotEmpty
                    ? _buildMemoryImage(
                        memory.imageUrl,
                        height: 220,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: Container(
                          height: 200,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: grad),
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
                        height: 200,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: grad),
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
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (memory.mediaType == 'video') ...[
              const SizedBox(height: 4),
              const Row(
                children: [
                  Icon(Icons.video_collection_rounded, size: 14, color: Colors.blue),
                  SizedBox(width: 4),
                  Text('Video Memory', style: TextStyle(fontSize: 11, color: Colors.blue)),
                ],
              ),
            ],
          ],
        ),
        actions: [
          if (memory.mediaType == 'video')
            FilledButton.icon(
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              label: const Text('Play Video'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF258CF4),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                _playVideo(memory.imageUrl);
              },
            ),
          if (canDelete)
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _deleteMemory(memory);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
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

  Future<void> _playVideo(String url) async {
    if (url.isEmpty) return;
    try {
      if (url.startsWith('http://') || url.startsWith('https://')) {
        final uri = Uri.parse(url);
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (!launched) {
          await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
        }
      } else {
        final fileUri = Uri.file(url);
        final launched = await launchUrl(
          fileUri,
          mode: LaunchMode.externalApplication,
        );
        if (!launched) {
          await launchUrl(fileUri);
        }
      }
    } catch (e) {
      developer.log('Video launch error: $e', name: 'SharedMemories');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not play video: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Widget _buildMemoryImage(
    String url, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
    required Widget placeholder,
  }) {
    if (url.isEmpty) return placeholder;

    // 1. Check local file on disk
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      if (url.startsWith('data:image')) {
        try {
          final commaIdx = url.indexOf(',');
          final b64 = commaIdx != -1 ? url.substring(commaIdx + 1) : url;
          final bytes = base64Decode(b64);
          return Image.memory(
            bytes,
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (_, _, _) => placeholder,
          );
        } catch (_) {}
      }

      final file = File(url);
      if (file.existsSync()) {
        return Image.file(
          file,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, _, _) => placeholder,
        );
      }
    }

    // 2. Remote Network image
    return Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, _, _) => placeholder,
    );
  }
}
