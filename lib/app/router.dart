import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tripcrew/features/auth/presentation/auth_gate.dart';
import 'package:tripcrew/features/auth/presentation/sign_in_screen.dart';
import 'package:tripcrew/features/auth/presentation/sign_up_screen.dart';
import 'package:tripcrew/features/auth/presentation/welcome_screen.dart';
import 'package:tripcrew/features/checklist/presentation/checklist_screen.dart';
import 'package:tripcrew/features/crew/presentation/crew_screen.dart';
import 'package:tripcrew/features/expenses/presentation/expenses_screen.dart';
import 'package:tripcrew/features/explorer/presentation/nearby_explorer_screen.dart';
import 'package:tripcrew/features/home/presentation/home_screen.dart';
import 'package:tripcrew/features/itinerary/presentation/itinerary_screen.dart';
import 'package:tripcrew/features/maps/presentation/live_crew_location_screen.dart';
import 'package:tripcrew/features/memories/presentation/shared_memories_screen.dart';
import 'package:tripcrew/features/payments/presentation/wallet_pay_screen.dart';
import 'package:tripcrew/features/payments/presentation/wallet_screen.dart';
import 'package:tripcrew/features/profile/presentation/profile_screen.dart';
import 'package:tripcrew/features/pulse/presentation/trip_pulse_screen.dart';
import 'package:tripcrew/features/recap/presentation/trip_recap_screen.dart';
import 'package:tripcrew/features/safety/presentation/safety_sos_screen.dart';
import 'package:tripcrew/features/shared/presentation/app_shell.dart';
import 'package:tripcrew/features/trips/models/trip_model.dart';
import 'package:tripcrew/features/trips/presentation/create_trip_screen.dart';
import 'package:tripcrew/features/trips/presentation/join_trip_screen.dart';
import 'package:tripcrew/features/trips/presentation/trip_created_screen.dart';
import 'package:tripcrew/features/trips/presentation/trips_screen.dart';
import 'package:tripcrew/features/trips/providers/trips_provider.dart';
import 'package:tripcrew/features/workspace/presentation/trip_workspace_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Central GoRouter configuration managing top-level tabs and feature navigation.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    routes: [
      // Authentication Routes
      GoRoute(
        path: '/welcome',
        name: 'welcome',
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/signup',
        name: 'signup',
        builder: (context, state) => const SignUpScreen(),
      ),
      GoRoute(
        path: '/signin',
        name: 'signin',
        builder: (context, state) => const SignInScreen(),
      ),

      // Trip Lifecycle Subroutes
      GoRoute(
        path: '/create-trip',
        name: 'create-trip',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const CreateTripScreen(),
      ),
      GoRoute(
        path: '/trip-created',
        name: 'trip-created',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final trip =
              state.extra as TripModel? ??
              ref.read(tripsProvider).activeTrip ??
              TripModel(
                id: 'trip_${DateTime.now().millisecondsSinceEpoch}',
                ownerId: 'owner',
                name: 'New Trip',
                startingPlace: 'Origin',
                destination: 'Destination',
                startDate: DateTime.now(),
                endDate: DateTime.now().add(const Duration(days: 3)),
                inviteCode: 'TRIP-CODE',
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              );
          return TripCreatedScreen(trip: trip);
        },
      ),
      GoRoute(
        path: '/join-trip',
        name: 'join-trip',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const JoinTripScreen(),
      ),

      // Trip Workspace & Feature Modules
      GoRoute(
        path: '/workspace',
        name: 'workspace',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const TripWorkspaceScreen(),
      ),
      GoRoute(
        path: '/crew',
        name: 'crew',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const CrewScreen(),
      ),
      GoRoute(
        path: '/itinerary',
        name: 'itinerary',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const ItineraryScreen(),
      ),
      GoRoute(
        path: '/checklist',
        name: 'checklist',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const ChecklistScreen(),
      ),
      GoRoute(
        path: '/expenses',
        name: 'expenses',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const ExpensesScreen(),
      ),
      GoRoute(
        path: '/wallet-pay',
        name: 'wallet-pay',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const WalletPayScreen(),
      ),
      GoRoute(
        path: '/live-location',
        name: 'live-location',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const LiveCrewLocationScreen(),
      ),
      GoRoute(
        path: '/pulse',
        name: 'pulse',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const TripPulseScreen(),
      ),
      GoRoute(
        path: '/memories',
        name: 'memories',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const SharedMemoriesScreen(),
      ),
      GoRoute(
        path: '/safety',
        name: 'safety',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const SafetySosScreen(),
      ),
      GoRoute(
        path: '/recap',
        name: 'recap',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const TripRecapScreen(),
      ),

      // Top-Level Persistent Bottom Navigation Shell (Home, Trips, Wallet, Explore, Profile)
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AuthGate(child: AppShell(navigationShell: navigationShell));
        },
        branches: [
          // Branch 0: Home
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                name: 'home',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: HomeScreen()),
              ),
            ],
          ),

          // Branch 1: Trips
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/trips',
                name: 'trips',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: TripsScreen()),
              ),
            ],
          ),

          // Branch 2: Wallet
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/wallet',
                name: 'wallet',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: WalletScreen()),
              ),
            ],
          ),

          // Branch 3: Explore
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/explore',
                name: 'explore',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: NearbyExplorerScreen()),
              ),
            ],
          ),

          // Branch 4: Profile
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                name: 'profile',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: ProfileScreen()),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
