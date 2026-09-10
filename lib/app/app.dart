import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tripcrew/app/router.dart';
import 'package:tripcrew/app/theme.dart';
import 'package:tripcrew/core/constants/app_constants.dart';

/// Root application widget configuring MaterialApp with GoRouter and AppTheme.
class TripCrewApp extends ConsumerWidget {
  const TripCrewApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
