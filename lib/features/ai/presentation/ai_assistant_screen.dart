import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tripcrew/features/ai/presentation/ai_assistant_dialog.dart';

/// Full-screen view for the OpenRouter-powered TripCrew AI Travel Assistant (default: NVIDIA Nemotron 3.5 Super VL).
/// Launched when tapping the AI notification or opening the dedicated AI Assistant view.
class AiAssistantScreen extends ConsumerWidget {
  const AiAssistantScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Scaffold(
      backgroundColor: Color(0xFF0F1B2B),
      body: AiAssistantDialog(isFullScreen: true),
    );
  }
}

