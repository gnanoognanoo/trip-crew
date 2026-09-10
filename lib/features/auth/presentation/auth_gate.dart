import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tripcrew/core/widgets/app_loading_indicator.dart';
import 'package:tripcrew/features/auth/presentation/welcome_screen.dart';
import 'package:tripcrew/features/auth/providers/auth_provider.dart';

/// AuthGate redirecting unauthenticated users to WelcomeScreen.
class AuthGate extends ConsumerWidget {
  final Widget child;

  const AuthGate({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    if (authState.isLoading) {
      return const Scaffold(
        body: AppLoadingIndicator(message: 'Starting TripCrew...'),
      );
    }

    if (!authState.isAuthenticated) {
      return const WelcomeScreen();
    }

    return child;
  }
}
