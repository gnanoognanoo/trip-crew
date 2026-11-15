import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tripcrew/app/router.dart';
import 'package:tripcrew/app/theme.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/core/services/notification_service.dart';
import 'package:tripcrew/core/services/trip_notification_watcher.dart';
import 'package:tripcrew/features/auth/providers/auth_provider.dart';
import 'package:tripcrew/features/trips/providers/trips_provider.dart';

/// Root application widget configuring MaterialApp with GoRouter, AppTheme,
/// and proactive out-of-app notification listening for the active crew trip.
class TripCrewApp extends ConsumerStatefulWidget {
  const TripCrewApp({super.key});

  @override
  ConsumerState<TripCrewApp> createState() => _TripCrewAppState();
}

class _TripCrewAppState extends ConsumerState<TripCrewApp> {
  @override
  void initState() {
    super.initState();
    NotificationService.onNotificationTapped = (payload) {
      if (payload != null && payload.isNotEmpty && mounted) {
        final router = ref.read(routerProvider);
        if (payload == '/explore') {
          router.push('/budget-explorer');
        } else {
          router.push(payload);
        }
      }
    };
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final activeTrip = ref.watch(activeTripProvider);
    final authState = ref.watch(authProvider);
    final user = authState.user;

    // Reactively connect trip notification watcher
    if (activeTrip != null && user != null) {
      TripNotificationWatcher.instance.watchTrip(
        tripId: activeTrip.id,
        currentUserId: user.uid,
      );
    } else {
      TripNotificationWatcher.instance.stop();
    }

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      routerConfig: router,
    );
  }
}
