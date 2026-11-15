import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:tripcrew/core/services/location_service.dart';
import 'package:tripcrew/core/services/supabase_service.dart';
import 'package:tripcrew/features/auth/providers/auth_provider.dart';
import 'package:tripcrew/features/chat/models/chat_message.dart';
import 'package:tripcrew/features/trips/providers/trips_provider.dart';

/// Screen: Real-time Crew Chatroom with Text, Voice Messages, and Live Location Pins.
class CrewChatScreen extends ConsumerStatefulWidget {
  const CrewChatScreen({super.key});

  @override
  ConsumerState<CrewChatScreen> createState() => _CrewChatScreenState();
}

class _CrewChatScreenState extends ConsumerState<CrewChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<ChatMessage> _messages = [];
  bool _isLoading = true;
  String? _currentUserId;
  String _currentUserName = 'Traveler';

  // Voice recording state
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  int _recordDurationSeconds = 0;
  Timer? _recordTimer;
  String? _recordedFilePath;

  // Audio playback state
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _currentlyPlayingMessageId;
  PlayerState _playerState = PlayerState.stopped;

  // Real-time & Polling subscriptions
  StreamSubscription? _messagesStreamSub;
  Timer? _pollingTimer;

  // Location sharing
  bool _isSharingLocation = false;

  @override
  void initState() {
    super.initState();
    _initUser();
    _fetchMessages();
    _setupRealtime();

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playerState = state);
    });
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _currentlyPlayingMessageId = null;
          _playerState = PlayerState.stopped;
        });
      }
    });

    // Fallback sync polling every 4 seconds
    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _fetchMessages(silent: true);
    });
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _pollingTimer?.cancel();
    _messagesStreamSub?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _initUser() async {
    final user = ref.read(authProvider).user;
    if (user != null && user.uid.isNotEmpty) {
      _currentUserId = user.uid;
      _currentUserName = user.name.isNotEmpty && user.name != 'Traveler' ? user.name : 'Traveler';
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      _currentUserId = prefs.getString('persistent_traveler_uid') ??
          'traveler_${DateTime.now().millisecondsSinceEpoch}';
      _currentUserName = prefs.getString('user_custom_name') ??
          prefs.getString('persistent_traveler_name') ??
          'Traveler';
    } catch (_) {
      _currentUserId = 'traveler_${DateTime.now().millisecondsSinceEpoch}';
      _currentUserName = 'Traveler';
    }
  }

  Future<void> _fetchMessages({bool silent = false}) async {
    final activeTrip = ref.read(activeTripProvider);
    if (activeTrip == null) {
      if (!silent && mounted) setState(() => _isLoading = false);
      return;
    }

    if (SupabaseService.isInitialized) {
      try {
        final res = await SupabaseService.client
            .from('chat_messages')
            .select()
            .eq('trip_id', activeTrip.id)
            .order('created_at', ascending: true);

        final loaded = res.map((r) => ChatMessage.fromMap(r)).toList();

        if (mounted) {
          final hadDifferentCount = loaded.length != _messages.length;
          setState(() {
            _messages.clear();
            _messages.addAll(loaded);
            _isLoading = false;
          });
          if (hadDifferentCount) {
            _scrollToBottom();
          }
        }
      } catch (e) {
        if (!silent && mounted) setState(() => _isLoading = false);
      }
    } else {
      if (!silent && mounted) setState(() => _isLoading = false);
    }
  }

  void _setupRealtime() {
    final activeTrip = ref.read(activeTripProvider);
    if (activeTrip == null || !SupabaseService.isInitialized) return;

    try {
      _messagesStreamSub = SupabaseService.client
          .from('chat_messages')
          .stream(primaryKey: ['id'])
          .eq('trip_id', activeTrip.id)
          .listen((_) {
            _fetchMessages(silent: true);
          }, onError: (_) {});
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 60,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // --- Send Text Message ---
  Future<void> _sendTextMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final activeTrip = ref.read(activeTripProvider);
    if (activeTrip == null) return;

    _textController.clear();
    await _initUser();

    final msgId = 'msg_${DateTime.now().millisecondsSinceEpoch}';
    final newMsg = ChatMessage(
      id: msgId,
      tripId: activeTrip.id,
      userId: _currentUserId ?? 'traveler',
      userName: _currentUserName,
      messageType: MessageType.text,
      content: text,
      createdAt: DateTime.now(),
    );

    setState(() => _messages.add(newMsg));
    _scrollToBottom();

    if (SupabaseService.isInitialized) {
      try {
        await SupabaseService.client.from('chat_messages').insert(newMsg.toMap());
      } catch (e) {
        debugPrint('[CrewChat] Insert error: $e');
      }
    }
  }

  // --- Voice Message Recording & Sending ---
  Future<void> _startVoiceRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final tempDir = await getTemporaryDirectory();
        final filePath = '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: filePath,
        );

        setState(() {
          _isRecording = true;
          _recordDurationSeconds = 0;
          _recordedFilePath = filePath;
        });

        _recordTimer?.cancel();
        _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (mounted) {
            setState(() => _recordDurationSeconds = timer.tick);
          }
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission required for voice notes.')),
          );
        }
      }
    } catch (e) {
      debugPrint('[CrewChat] Record start error: $e');
    }
  }

  Future<void> _cancelVoiceRecording() async {
    _recordTimer?.cancel();
    try {
      await _audioRecorder.stop();
    } catch (_) {}
    setState(() {
      _isRecording = false;
      _recordDurationSeconds = 0;
      _recordedFilePath = null;
    });
  }

  Future<void> _sendVoiceRecording() async {
    _recordTimer?.cancel();
    final activeTrip = ref.read(activeTripProvider);
    if (activeTrip == null) return;

    String? finalPath;
    try {
      finalPath = await _audioRecorder.stop();
    } catch (e) {
      debugPrint('[CrewChat] Record stop error: $e');
    }

    final duration = _recordDurationSeconds;
    setState(() {
      _isRecording = false;
      _recordDurationSeconds = 0;
    });

    final targetPath = finalPath ?? _recordedFilePath;
    if (targetPath == null || duration < 1) return;

    await _initUser();
    final msgId = 'voice_${DateTime.now().millisecondsSinceEpoch}';

    String audioPayload = targetPath;

    // Upload to Supabase Storage if available
    if (SupabaseService.isInitialized) {
      try {
        final file = File(targetPath);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final fileName = 'voice_${activeTrip.id}_$msgId.m4a';
          await SupabaseService.client.storage.from('trip-audio').uploadBinary(
                fileName,
                bytes,
              );
          final publicUrl = SupabaseService.client.storage.from('trip-audio').getPublicUrl(fileName);
          if (publicUrl.isNotEmpty) {
            audioPayload = publicUrl;
          }
        }
      } catch (e) {
        debugPrint('[CrewChat] Audio upload warning: $e');
      }
    }

    final newMsg = ChatMessage(
      id: msgId,
      tripId: activeTrip.id,
      userId: _currentUserId ?? 'traveler',
      userName: _currentUserName,
      messageType: MessageType.voice,
      content: audioPayload,
      audioDurationSeconds: duration,
      createdAt: DateTime.now(),
    );

    setState(() => _messages.add(newMsg));
    _scrollToBottom();

    if (SupabaseService.isInitialized) {
      try {
        await SupabaseService.client.from('chat_messages').insert(newMsg.toMap());
      } catch (e) {
        debugPrint('[CrewChat] Insert voice message error: $e');
      }
    }
  }

  // --- Voice Playback ---
  Future<void> _togglePlayVoice(ChatMessage msg) async {
    if (_currentlyPlayingMessageId == msg.id && _playerState == PlayerState.playing) {
      await _audioPlayer.pause();
      return;
    }

    try {
      await _audioPlayer.stop();
      setState(() {
        _currentlyPlayingMessageId = msg.id;
        _playerState = PlayerState.playing;
      });

      if (msg.content.startsWith('http://') || msg.content.startsWith('https://')) {
        await _audioPlayer.play(UrlSource(msg.content));
      } else {
        await _audioPlayer.play(DeviceFileSource(msg.content));
      }
    } catch (e) {
      debugPrint('[CrewChat] Audio play error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not play voice message.')),
        );
      }
    }
  }

  // --- Share Live Location ---
  Future<void> _shareLiveLocation() async {
    if (_isSharingLocation) return;
    final activeTrip = ref.read(activeTripProvider);
    if (activeTrip == null) return;

    setState(() => _isSharingLocation = true);

    try {
      final pos = await LocationService.getFreshLocation();
      if (pos == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission required to share live pin.')),
          );
        }
        return;
      }

      await _initUser();
      final msgId = 'loc_${DateTime.now().millisecondsSinceEpoch}';

      final newMsg = ChatMessage(
        id: msgId,
        tripId: activeTrip.id,
        userId: _currentUserId ?? 'traveler',
        userName: _currentUserName,
        messageType: MessageType.location,
        content: '📍 Live Location Pin: ${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}',
        latitude: pos.latitude,
        longitude: pos.longitude,
        createdAt: DateTime.now(),
      );

      setState(() => _messages.add(newMsg));
      _scrollToBottom();

      if (SupabaseService.isInitialized) {
        try {
          await SupabaseService.client.from('chat_messages').insert(newMsg.toMap());
        } catch (_) {}
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📍 Live Location pinned to Crew Chatroom!'),
            backgroundColor: Color(0xFF10B981),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share location: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSharingLocation = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final activeTrip = ref.watch(activeTripProvider);

    if (activeTrip == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Crew Chat')),
        body: const Center(child: Text('No active trip selected.')),
      );
    }

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
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${activeTrip.name} Crew Chat',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${activeTrip.memberCount} members • Live Chatroom',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ],
          ),
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
            IconButton(
              icon: _isSharingLocation
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981)),
                    )
                  : const Icon(Icons.location_on_rounded, color: Color(0xFF10B981)),
              tooltip: 'Share Live Location Pin',
              onPressed: _shareLiveLocation,
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh Messages',
              onPressed: () => _fetchMessages(),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Chat Messages Area
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _messages.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    size: 40,
                                    color: Color(0xFF3B82F6),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Crew Chatroom is Ready!',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Send text, record voice messages, or share live location.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? Colors.white60 : Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              final msg = _messages[index];
                              final isMe = msg.isMe(_currentUserId ?? '');
                              return _buildMessageItem(msg, isMe, isDark);
                            },
                          ),
              ),

              // Bottom Input Bar
              _buildBottomBar(isDark),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteMessage(ChatMessage msg) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Message?'),
        content: Text(
          msg.isVoice
              ? 'Are you sure you want to delete this voice message?'
              : (msg.isLocation
                  ? 'Are you sure you want to remove this location pin?'
                  : 'Are you sure you want to delete this message?'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // 1. Optimistically delete from UI
    setState(() {
      _messages.removeWhere((m) => m.id == msg.id);
    });

    // 2. Delete from Supabase Database
    if (SupabaseService.isInitialized) {
      try {
        await SupabaseService.client.from('chat_messages').delete().eq('id', msg.id);
      } catch (e) {
        debugPrint('[CrewChat] Error deleting message from Supabase: $e');
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message deleted')),
      );
    }
  }

  void _showMessageOptions(ChatMessage msg) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ListTile(
                  leading: Icon(
                    msg.isVoice
                        ? Icons.mic_rounded
                        : (msg.isLocation ? Icons.location_on_rounded : Icons.chat_bubble_outline_rounded),
                    color: const Color(0xFF3B82F6),
                  ),
                  title: Text(
                    msg.isVoice
                        ? 'Voice Message (${msg.formattedAudioDuration})'
                        : (msg.isLocation ? 'Shared Location Pin' : 'Text Message'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('Sent by ${msg.userName} at ${msg.formattedTime}'),
                ),
                if (msg.isText)
                  ListTile(
                    leading: const Icon(Icons.copy_rounded),
                    title: const Text('Copy Text'),
                    onTap: () {
                      Navigator.pop(ctx);
                      Clipboard.setData(ClipboardData(text: msg.content));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied to clipboard')),
                      );
                    },
                  ),
                if (msg.isLocation && msg.latitude != null && msg.longitude != null)
                  ListTile(
                    leading: const Icon(Icons.map_rounded, color: Color(0xFF2563EB)),
                    title: const Text('Open in Google Maps'),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=${msg.latitude},${msg.longitude}');
                      try {
                        await launchUrl(url, mode: LaunchMode.externalApplication);
                      } catch (_) {}
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.delete_forever_rounded, color: Colors.red),
                  title: const Text(
                    'Delete Message',
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text('Permanently remove this message from chat'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _deleteMessage(msg);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMessageItem(ChatMessage msg, bool isMe, bool isDark) {
    final bubbleColor = isMe
        ? const Color(0xFFFFE600)
        : (isDark ? const Color(0xFF1E2E42) : const Color(0xFFF1F5F9));
    final textColor = isMe ? Colors.black : (isDark ? Colors.white : Colors.black87);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // Member Name header for other members
          if (!isMe)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 3),
              child: Text(
                msg.userName,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF3B82F6),
                ),
              ),
            ),

          GestureDetector(
            onLongPress: () => _showMessageOptions(msg),
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78,
              ),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (msg.isText)
                    Text(
                      msg.content,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 14,
                        fontWeight: isMe ? FontWeight.w600 : FontWeight.w400,
                      ),
                    )
                  else if (msg.isVoice)
                    _buildVoiceBubble(msg, isMe, textColor)
                  else if (msg.isLocation)
                    _buildLocationBubble(msg, isMe, textColor),

                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        msg.formattedTime,
                        style: TextStyle(
                          fontSize: 10,
                          color: isMe ? Colors.black54 : (isDark ? Colors.white54 : Colors.black45),
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => _showMessageOptions(msg),
                        child: Icon(
                          Icons.more_horiz_rounded,
                          size: 14,
                          color: isMe ? Colors.black45 : (isDark ? Colors.white38 : Colors.black38),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceBubble(ChatMessage msg, bool isMe, Color textColor) {
    final isPlaying = _currentlyPlayingMessageId == msg.id && _playerState == PlayerState.playing;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
            color: isMe ? Colors.black87 : const Color(0xFF10B981),
            size: 34,
          ),
          onPressed: () => _togglePlayVoice(msg),
        ),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.mic_rounded, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  'Voice Note • ${msg.formattedAudioDuration}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Audio Waveform Visualization
            Row(
              children: List.generate(14, (i) {
                final height = 6 + (i * 7 % 14);
                return Container(
                  width: 3,
                  height: height.toDouble(),
                  margin: const EdgeInsets.only(right: 3),
                  decoration: BoxDecoration(
                    color: isPlaying ? const Color(0xFF10B981) : (isMe ? Colors.black38 : Colors.grey),
                    borderRadius: BorderRadius.circular(2),
                  ),
                );
              }),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLocationBubble(ChatMessage msg, bool isMe, Color textColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: Color(0xFF10B981),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.location_on_rounded, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 8),
            Text(
              'Live Location Pin',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: textColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Lat: ${msg.latitude?.toStringAsFixed(4)}, Lng: ${msg.longitude?.toStringAsFixed(4)}',
          style: TextStyle(fontSize: 12, color: textColor),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () async {
                  if (msg.latitude == null || msg.longitude == null) return;
                  final lat = msg.latitude;
                  final lng = msg.longitude;
                  final gmapsUri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
                  try {
                    await launchUrl(gmapsUri, mode: LaunchMode.externalApplication);
                  } catch (_) {}
                },
                icon: const Icon(Icons.map_rounded, size: 15),
                label: const Text('Google Maps', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: () {
                  context.push('/live-location');
                },
                icon: const Icon(Icons.radar_rounded, size: 15),
                label: const Text('Crew Radar', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                style: FilledButton.styleFrom(
                  backgroundColor: isMe ? Colors.black : const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBottomBar(bool isDark) {
    if (_isRecording) {
      final m = _recordDurationSeconds ~/ 60;
      final s = _recordDurationSeconds % 60;
      final timeStr = '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF162332) : Colors.white,
          border: Border(top: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0))),
        ),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                color: Colors.redAccent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Recording $timeStr...',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              tooltip: 'Discard Voice Note',
              onPressed: _cancelVoiceRecording,
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: const Icon(Icons.send_rounded),
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFFFE600),
                foregroundColor: Colors.black,
              ),
              tooltip: 'Send Voice Note',
              onPressed: _sendVoiceRecording,
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF162332) : Colors.white,
        border: Border(top: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          // Share Location Quick Button
          IconButton(
            icon: const Icon(Icons.pin_drop_rounded, color: Color(0xFF10B981)),
            tooltip: 'Share Live Location Pin',
            onPressed: _shareLiveLocation,
          ),

          // Text Field
          Expanded(
            child: TextField(
              controller: _textController,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendTextMessage(),
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Message crew...',
                hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
                filled: true,
                fillColor: isDark ? const Color(0xFF1C2A3A) : const Color(0xFFF1F5F9),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),

          // Mic button for recording voice note
          IconButton(
            icon: const Icon(Icons.mic_rounded),
            style: IconButton.styleFrom(
              backgroundColor: isDark ? const Color(0xFF1C2A3A) : const Color(0xFFF1F5F9),
              foregroundColor: const Color(0xFF10B981),
            ),
            tooltip: 'Record Voice Note',
            onPressed: _startVoiceRecording,
          ),

          const SizedBox(width: 4),

          // Send button
          IconButton(
            icon: const Icon(Icons.send_rounded),
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFFFFE600),
              foregroundColor: Colors.black,
            ),
            tooltip: 'Send Message',
            onPressed: _sendTextMessage,
          ),
        ],
      ),
    );
  }
}

