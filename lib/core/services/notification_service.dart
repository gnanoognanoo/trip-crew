import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Centralized Notification Service for showing native Android status bar
/// and out-of-app notifications for TripCrew events (chat, pulses, expenses, members).
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// Global callback for handling notification taps
  static void Function(String? payload)? onNotificationTapped;

  /// Initializes the notification service with Android and iOS channels.
  Future<void> initialize({void Function(String? payload)? onSelectNotification}) async {
    if (_isInitialized) return;

    if (onSelectNotification != null) {
      onNotificationTapped = onSelectNotification;
    }

    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const initSettings = InitializationSettings(
        android: androidInit,
        iOS: iosInit,
      );

      await _notificationsPlugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          developer.log(
            'Notification tapped with payload: ${response.payload}',
            name: 'NotificationService',
          );
          onNotificationTapped?.call(response.payload);
        },
      );

      // Create Android Notification Channels for high priority alerts
      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            'tripcrew_alerts',
            'TripCrew Trip Updates',
            description: 'Notifications for pulses, expenses, itinerary, and member updates',
            importance: Importance.max,
            enableVibration: true,
            playSound: true,
          ),
        );

        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            'tripcrew_chat',
            'TripCrew Chat Messages',
            description: 'Instant messages, location pins, and voice notes from your travel crew',
            importance: Importance.max,
            enableVibration: true,
            playSound: true,
          ),
        );

        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            'tripcrew_media',
            'TripCrew Shared Memories',
            description: 'Photos and media uploaded by your crew members',
            importance: Importance.max,
            enableVibration: true,
            playSound: true,
          ),
        );

        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            'tripcrew_ai',
            'TripCrew AI Travel Assistant',
            description: 'AI travel insights, recommendations, and answered questions',
            importance: Importance.max,
            enableVibration: true,
            playSound: true,
          ),
        );

        // Request POST_NOTIFICATIONS permission for Android 13+
        await androidPlugin.requestNotificationsPermission();
      }

      _isInitialized = true;
      developer.log('NotificationService initialized successfully', name: 'NotificationService');
    } catch (e, stack) {
      developer.log('Failed to initialize NotificationService: $e', name: 'NotificationService', stackTrace: stack);
    }
  }

  static String _getChannelName(String channelId) {
    switch (channelId) {
      case 'tripcrew_chat':
        return 'TripCrew Chat Messages';
      case 'tripcrew_media':
        return 'TripCrew Shared Memories';
      case 'tripcrew_ai':
        return 'TripCrew AI Assistant';
      case 'tripcrew_alerts':
      default:
        return 'TripCrew Trip Updates';
    }
  }

  /// Triggers a native out-of-app notification in Android status bar / shade
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
    String channelId = 'tripcrew_alerts',
  }) async {
    try {
      final androidDetails = AndroidNotificationDetails(
        channelId,
        _getChannelName(channelId),
        channelDescription: 'Out-of-app notification for TripCrew',
        importance: Importance.max,
        priority: Priority.max,
        showWhen: true,
        enableVibration: true,
        playSound: true,
        ticker: title,
        color: const Color(0xFFFFD600),
        icon: '@mipmap/ic_launcher',
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notificationsPlugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
        payload: payload,
      );
    } catch (e) {
      developer.log('Error showing notification: $e', name: 'NotificationService');
    }
  }
}

