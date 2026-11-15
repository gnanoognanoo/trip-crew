import 'dart:async';
import 'dart:developer' as developer;
import 'package:tripcrew/core/services/notification_service.dart';
import 'package:tripcrew/core/services/supabase_service.dart';

/// Realtime and active high-frequency watcher that listens for all trip events
/// (chat messages, pulses, media uploads, expenses, itinerary, member joins)
/// and triggers native out-of-app OS notifications in the Android Notification Center immediately.
class TripNotificationWatcher {
  TripNotificationWatcher._();
  static final TripNotificationWatcher instance = TripNotificationWatcher._();

  StreamSubscription? _chatSub;
  StreamSubscription? _pulseSub;
  StreamSubscription? _expenseSub;
  StreamSubscription? _memberSub;
  StreamSubscription? _memorySub;
  StreamSubscription? _itinerarySub;

  Timer? _pollingTimer;

  String? _currentTripId;
  String? _currentUserId;

  bool _isFirstChatLoad = true;
  bool _isFirstPulseLoad = true;
  bool _isFirstExpenseLoad = true;
  bool _isFirstMemberLoad = true;
  bool _isFirstMemoryLoad = true;
  bool _isFirstItineraryLoad = true;
  bool _isInitialSyncDone = false;

  // Track already notified IDs to prevent duplicate notifications
  final Set<String> _seenMessageIds = {};
  final Set<String> _seenPulseIds = {};
  final Set<String> _seenExpenseIds = {};
  final Set<String> _seenMemberIds = {};
  final Set<String> _seenMemoryIds = {};
  final Set<String> _seenItineraryIds = {};

  // Stream controller to notify in-app UI (like HomeScreen notification bell) of new events
  final _onNewEventController = StreamController<String>.broadcast();
  Stream<String> get onNewEventStream => _onNewEventController.stream;

  /// Public trigger to immediately notify in-app UI listeners of local events
  void notifyLocalEvent(String type) {
    if (!_onNewEventController.isClosed) {
      _onNewEventController.add(type);
    }
  }

  /// Starts watching notifications for the specified trip and current user.
  void watchTrip({
    required String tripId,
    required String currentUserId,
  }) {
    if (_currentTripId == tripId && _currentUserId == currentUserId) {
      return;
    }

    stop();
    _currentTripId = tripId;
    _currentUserId = currentUserId;

    _isFirstChatLoad = true;
    _isFirstPulseLoad = true;
    _isFirstExpenseLoad = true;
    _isFirstMemberLoad = true;
    _isFirstMemoryLoad = true;
    _isFirstItineraryLoad = true;
    _isInitialSyncDone = false;

    if (!SupabaseService.isInitialized) return;

    // 1. Start Realtime WebSocket Subscriptions
    _listenChatMessages(tripId, currentUserId);
    _listenTripPulses(tripId, currentUserId);
    _listenExpenses(tripId, currentUserId);
    _listenTripMembers(tripId, currentUserId);
    _listenMemories(tripId, currentUserId);
    _listenItinerary(tripId, currentUserId);

    // 2. Immediate Initial Fetch and Fast Polling (every 2.5 seconds)
    // Guarantees instant notifications even if WebSocket drops or CDC isn't publishing!
    _syncLatestEvents(tripId, currentUserId);
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      _syncLatestEvents(tripId, currentUserId);
    });
  }

  // --- Realtime Streams ---
  void _listenChatMessages(String tripId, String currentUserId) {
    try {
      _chatSub = SupabaseService.client
          .from('chat_messages')
          .stream(primaryKey: ['id'])
          .eq('trip_id', tripId)
          .listen((data) {
            if (_isFirstChatLoad) {
              for (final row in data) {
                final id = row['id']?.toString() ?? '';
                if (id.isNotEmpty) _seenMessageIds.add(id);
              }
              _isFirstChatLoad = false;
              return;
            }

            for (final row in data) {
              _handleNewChatMessage(row, currentUserId);
            }
          }, onError: (e) {
            developer.log('Chat realtime stream error: $e', name: 'NotificationWatcher');
          });
    } catch (e) {
      developer.log('Error listening to chat messages: $e', name: 'NotificationWatcher');
    }
  }

  void _listenTripPulses(String tripId, String currentUserId) {
    try {
      _pulseSub = SupabaseService.client
          .from('trip_pulses')
          .stream(primaryKey: ['id'])
          .eq('trip_id', tripId)
          .listen((data) {
            if (_isFirstPulseLoad) {
              for (final row in data) {
                final pulseKey = '${row['id']}_${row['created_at']}_${row['pulse_type']}';
                if (pulseKey.isNotEmpty) _seenPulseIds.add(pulseKey);
              }
              _isFirstPulseLoad = false;
              return;
            }

            for (final row in data) {
              _handleNewPulse(row, currentUserId);
            }
          }, onError: (e) {
            developer.log('Pulse stream error: $e', name: 'NotificationWatcher');
          });
    } catch (e) {
      developer.log('Error listening to pulses: $e', name: 'NotificationWatcher');
    }
  }

  void _listenExpenses(String tripId, String currentUserId) {
    try {
      _expenseSub = SupabaseService.client
          .from('expenses')
          .stream(primaryKey: ['id'])
          .eq('trip_id', tripId)
          .listen((data) {
            if (_isFirstExpenseLoad) {
              for (final row in data) {
                final id = row['id']?.toString() ?? '';
                if (id.isNotEmpty) _seenExpenseIds.add(id);
              }
              _isFirstExpenseLoad = false;
              return;
            }

            for (final row in data) {
              _handleNewExpense(row, currentUserId);
            }
          }, onError: (e) {
            developer.log('Expenses stream error: $e', name: 'NotificationWatcher');
          });
    } catch (e) {
      developer.log('Error listening to expenses: $e', name: 'NotificationWatcher');
    }
  }

  void _listenTripMembers(String tripId, String currentUserId) {
    try {
      _memberSub = SupabaseService.client
          .from('trip_members')
          .stream(primaryKey: ['id'])
          .eq('trip_id', tripId)
          .listen((data) {
            if (_isFirstMemberLoad) {
              for (final row in data) {
                final id = row['id']?.toString() ?? '';
                if (id.isNotEmpty) _seenMemberIds.add(id);
              }
              _isFirstMemberLoad = false;
              return;
            }

            for (final row in data) {
              _handleNewMember(row, currentUserId);
            }
          }, onError: (e) {
            developer.log('Members stream error: $e', name: 'NotificationWatcher');
          });
    } catch (e) {
      developer.log('Error listening to members: $e', name: 'NotificationWatcher');
    }
  }

  void _listenMemories(String tripId, String currentUserId) {
    try {
      _memorySub = SupabaseService.client
          .from('memories')
          .stream(primaryKey: ['id'])
          .eq('trip_id', tripId)
          .listen((data) {
            if (_isFirstMemoryLoad) {
              for (final row in data) {
                final id = row['id']?.toString() ?? '';
                if (id.isNotEmpty) _seenMemoryIds.add(id);
              }
              _isFirstMemoryLoad = false;
              return;
            }

            for (final row in data) {
              _handleNewMemory(row, currentUserId);
            }
          }, onError: (e) {
            developer.log('Memories stream error: $e', name: 'NotificationWatcher');
          });
    } catch (e) {
      developer.log('Error listening to memories: $e', name: 'NotificationWatcher');
    }
  }

  void _listenItinerary(String tripId, String currentUserId) {
    try {
      _itinerarySub = SupabaseService.client
          .from('itinerary_items')
          .stream(primaryKey: ['id'])
          .eq('trip_id', tripId)
          .listen((data) {
            if (_isFirstItineraryLoad) {
              for (final row in data) {
                final id = row['id']?.toString() ?? '';
                if (id.isNotEmpty) _seenItineraryIds.add(id);
              }
              _isFirstItineraryLoad = false;
              return;
            }

            for (final row in data) {
              _handleNewItinerary(row, currentUserId);
            }
          }, onError: (e) {
            developer.log('Itinerary stream error: $e', name: 'NotificationWatcher');
          });
    } catch (e) {
      developer.log('Error listening to itinerary: $e', name: 'NotificationWatcher');
    }
  }

  // --- Active Sync Poller (Runs every 2.5 seconds) ---
  Future<void> _syncLatestEvents(String tripId, String currentUserId) async {
    if (!SupabaseService.isInitialized) return;

    try {
      // 1. Chat Messages
      try {
        final messages = await SupabaseService.client
            .from('chat_messages')
            .select()
            .eq('trip_id', tripId)
            .order('created_at', ascending: false)
            .limit(10);

        if (!_isInitialSyncDone) {
          for (final row in messages) {
            final id = row['id']?.toString() ?? '';
            if (id.isNotEmpty) _seenMessageIds.add(id);
          }
        } else {
          for (final row in messages) {
            _handleNewChatMessage(row, currentUserId);
          }
        }
      } catch (_) {}

      // 2. Trip Pulses
      try {
        final pulses = await SupabaseService.client
            .from('trip_pulses')
            .select()
            .eq('trip_id', tripId)
            .order('created_at', ascending: false)
            .limit(8);

        if (!_isInitialSyncDone) {
          for (final row in pulses) {
            final pulseKey = '${row['id']}_${row['created_at']}_${row['pulse_type']}';
            if (pulseKey.isNotEmpty) _seenPulseIds.add(pulseKey);
          }
        } else {
          for (final row in pulses) {
            _handleNewPulse(row, currentUserId);
          }
        }
      } catch (_) {}

      // 3. Media Uploads (Memories)
      try {
        final memories = await SupabaseService.client
            .from('memories')
            .select()
            .eq('trip_id', tripId)
            .order('created_at', ascending: false)
            .limit(8);

        if (!_isInitialSyncDone) {
          for (final row in memories) {
            final id = row['id']?.toString() ?? '';
            if (id.isNotEmpty) _seenMemoryIds.add(id);
          }
        } else {
          for (final row in memories) {
            _handleNewMemory(row, currentUserId);
          }
        }
      } catch (_) {}

      // 4. Expenses
      try {
        final expenses = await SupabaseService.client
            .from('expenses')
            .select()
            .eq('trip_id', tripId)
            .order('created_at', ascending: false)
            .limit(8);

        if (!_isInitialSyncDone) {
          for (final row in expenses) {
            final id = row['id']?.toString() ?? '';
            if (id.isNotEmpty) _seenExpenseIds.add(id);
          }
        } else {
          for (final row in expenses) {
            _handleNewExpense(row, currentUserId);
          }
        }
      } catch (_) {}

      // 5. Itinerary Items
      try {
        final itinerary = await SupabaseService.client
            .from('itinerary_items')
            .select()
            .eq('trip_id', tripId)
            .order('created_at', ascending: false)
            .limit(8);

        if (!_isInitialSyncDone) {
          for (final row in itinerary) {
            final id = row['id']?.toString() ?? '';
            if (id.isNotEmpty) _seenItineraryIds.add(id);
          }
        } else {
          for (final row in itinerary) {
            _handleNewItinerary(row, currentUserId);
          }
        }
      } catch (_) {}

      // 6. Trip Members
      try {
        final members = await SupabaseService.client
            .from('trip_members')
            .select()
            .eq('trip_id', tripId)
            .order('joined_at', ascending: false)
            .limit(8);

        if (!_isInitialSyncDone) {
          for (final row in members) {
            final id = row['id']?.toString() ?? '';
            if (id.isNotEmpty) _seenMemberIds.add(id);
          }
        } else {
          for (final row in members) {
            _handleNewMember(row, currentUserId);
          }
        }
      } catch (_) {}

      if (!_isInitialSyncDone) {
        _isInitialSyncDone = true;
      }
    } catch (e) {
      developer.log('Error in active sync poll: $e', name: 'NotificationWatcher');
    }
  }

  // --- Handlers for New Rows ---

  void _handleNewChatMessage(Map<String, dynamic> row, String currentUserId) {
    final id = row['id']?.toString() ?? '';
    final senderId = row['user_id']?.toString() ?? '';
    final senderName = row['user_name']?.toString() ?? 'Crew Member';
    final type = row['message_type']?.toString() ?? 'text';
    final content = row['content']?.toString() ?? '';

    if (id.isNotEmpty && !_seenMessageIds.contains(id)) {
      _seenMessageIds.add(id);

      // ALWAYS trigger in-app UI listeners (for both current user and crew)
      _onNewEventController.add('chat');

      if (senderId != currentUserId) {
        String body = content;
        if (type == 'audio') {
          body = '🎤 Sent a voice message';
        } else if (type == 'location') {
          body = '📍 Shared live location pin';
        }

        NotificationService.instance.showNotification(
          id: id.hashCode,
          title: '💬 $senderName in Crew Chat',
          body: body,
          payload: '/chat',
          channelId: 'tripcrew_chat',
        );
      }
    }
  }

  void _handleNewPulse(Map<String, dynamic> row, String currentUserId) {
    final id = row['id']?.toString() ?? '';
    final createdAt = row['created_at']?.toString() ?? '';
    final pulseType = row['pulse_type']?.toString() ?? 'Status update';
    final pulseKey = '${id}_${createdAt}_$pulseType';
    final senderId = row['user_id']?.toString() ?? '';
    final senderName = row['user_name']?.toString() ?? 'Crew Member';
    final message = row['message']?.toString() ?? '';

    if (pulseKey.isNotEmpty && !_seenPulseIds.contains(pulseKey)) {
      _seenPulseIds.add(pulseKey);

      // ALWAYS trigger in-app UI listeners so pulse feed and notifications sheet update immediately
      _onNewEventController.add('pulse');

      if (senderId != currentUserId) {
        final bodyText = message.isNotEmpty ? 'Status: $pulseType • $message' : 'Status: $pulseType';
        NotificationService.instance.showNotification(
          id: pulseKey.hashCode,
          title: '💓 $senderName • Trip Pulse',
          body: bodyText,
          payload: '/pulse',
          channelId: 'tripcrew_alerts',
        );
      }
    }
  }

  void _handleNewMemory(Map<String, dynamic> row, String currentUserId) {
    final id = row['id']?.toString() ?? '';
    final uploaderId = (row['uploader_id'] ?? row['user_id'])?.toString() ?? '';
    final photographerName = (row['photographer_name'] ?? row['user_name'])?.toString() ?? 'Crew Member';
    final caption = row['caption']?.toString() ?? '';

    if (id.isNotEmpty && !_seenMemoryIds.contains(id)) {
      _seenMemoryIds.add(id);

      _onNewEventController.add('memory');

      if (uploaderId != currentUserId) {
        final bodyText = caption.isNotEmpty ? '$photographerName shared: "$caption"' : '$photographerName uploaded a new trip photo';
        NotificationService.instance.showNotification(
          id: id.hashCode,
          title: '📸 New Memory Photo Uploaded!',
          body: bodyText,
          payload: '/memories',
          channelId: 'tripcrew_media',
        );
      }
    }
  }

  void _handleNewExpense(Map<String, dynamic> row, String currentUserId) {
    final id = row['id']?.toString() ?? '';
    final payerId = row['paid_by_user_id']?.toString() ?? '';
    final payerName = row['paid_by_name']?.toString() ?? 'Crew Member';
    final desc = row['description']?.toString() ?? 'Trip expense';
    final amountPaise = row['amount_paise'] as num? ?? 0;
    final amountStr = amountPaise > 0 ? '₹${(amountPaise / 100).toStringAsFixed(0)}' : '';

    if (id.isNotEmpty && !_seenExpenseIds.contains(id)) {
      _seenExpenseIds.add(id);

      _onNewEventController.add('expense');

      if (payerId != currentUserId) {
        NotificationService.instance.showNotification(
          id: id.hashCode,
          title: '💳 Expense Logged',
          body: amountStr.isNotEmpty
              ? '$payerName logged $amountStr for $desc'
              : '$payerName logged $desc',
          payload: '/expenses',
          channelId: 'tripcrew_alerts',
        );
      }
    }
  }

  void _handleNewItinerary(Map<String, dynamic> row, String currentUserId) {
    final id = row['id']?.toString() ?? '';
    final creatorId = row['created_by']?.toString() ?? '';
    final title = row['title']?.toString() ?? 'New stop';
    final day = row['day_number'] ?? 1;
    final time = row['time'] ?? '';

    if (id.isNotEmpty && !_seenItineraryIds.contains(id)) {
      _seenItineraryIds.add(id);

      _onNewEventController.add('itinerary');

      if (creatorId != currentUserId) {
        NotificationService.instance.showNotification(
          id: id.hashCode,
          title: '📍 Itinerary Stop Added',
          body: '$title · Day $day ($time)',
          payload: '/itinerary',
          channelId: 'tripcrew_alerts',
        );
      }
    }
  }

  void _handleNewMember(Map<String, dynamic> row, String currentUserId) {
    final id = row['id']?.toString() ?? '';
    final memberId = row['user_id']?.toString() ?? '';
    final memberName = row['user_name']?.toString() ?? 'A companion';

    if (id.isNotEmpty && !_seenMemberIds.contains(id)) {
      _seenMemberIds.add(id);

      _onNewEventController.add('member');

      if (memberId != currentUserId) {
        NotificationService.instance.showNotification(
          id: id.hashCode,
          title: '🎒 New Crew Member Joined!',
          body: '$memberName entered the trip workspace.',
          payload: '/crew',
          channelId: 'tripcrew_alerts',
        );
      }
    }
  }

  /// Stops all subscriptions and active polling
  void stop() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _chatSub?.cancel();
    _pulseSub?.cancel();
    _expenseSub?.cancel();
    _memberSub?.cancel();
    _memorySub?.cancel();
    _itinerarySub?.cancel();
    _currentTripId = null;
    _currentUserId = null;
  }
}
