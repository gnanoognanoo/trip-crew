import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tripcrew/app/app.dart';
import 'package:tripcrew/core/services/firebase_service.dart';
import 'package:tripcrew/core/services/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase with multi-platform Crashlytics & Analytics
  await FirebaseService.initialize();

  // Initialize Supabase PostgreSQL Client
  await SupabaseService.initialize();

  runApp(const ProviderScope(child: TripCrewApp()));
}
