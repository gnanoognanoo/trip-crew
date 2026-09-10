import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tripcrew/core/errors/failure.dart';
import 'package:tripcrew/core/services/analytics_service.dart';
import 'package:tripcrew/core/services/firebase_service.dart';
import 'package:tripcrew/features/auth/models/user_profile.dart';

class AuthState {
  final bool isLoading;
  final UserProfile? user;
  final Failure? error;

  const AuthState({this.isLoading = false, this.user, this.error});

  bool get isAuthenticated => user != null;

  AuthState copyWith({
    bool? isLoading,
    UserProfile? user,
    Failure? error,
    bool clearError = false,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      user: user ?? this.user,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  StreamSubscription<User?>? _authSubscription;

  @override
  AuthState build() {
    ref.onDispose(() {
      _authSubscription?.cancel();
    });

    if (FirebaseService.isInitialized) {
      _init();
      return const AuthState(isLoading: true);
    } else {
      // Offline/local development fallback
      return const AuthState(isLoading: false, user: null);
    }
  }

  void _init() {
    if (FirebaseService.isInitialized) {
      _authSubscription = FirebaseAuth.instance.authStateChanges().listen(
        (firebaseUser) async {
          if (firebaseUser != null) {
            await _loadUserProfile(
              firebaseUser.uid,
              firebaseUser.email ?? '',
              firebaseUser.displayName,
            );
          } else {
            state = const AuthState(isLoading: false, user: null);
          }
        },
        onError: (e) {
          state = AuthState(
            isLoading: false,
            error: UnknownFailure(message: e.toString()),
          );
        },
      );
    }
  }

  Future<void> _loadUserProfile(
    String uid,
    String email,
    String? displayName,
  ) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (doc.exists && doc.data() != null) {
        final profile = UserProfile.fromMap(doc.data()!, uid);
        state = AuthState(user: profile, isLoading: false);
      } else {
        final newProfile = UserProfile(
          uid: uid,
          name: displayName ?? email.split('@').first,
          email: email,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'uid': uid,
          'name': newProfile.name,
          'email': email,
          'photoUrl': null,
          'tripCount': 0,
          'distanceKm': 0,
          'memoryCount': 0,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        state = AuthState(user: newProfile, isLoading: false);
      }
    } catch (_) {
      state = AuthState(
        user: UserProfile(
          uid: uid,
          name: displayName ?? email.split('@').first,
          email: email,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        isLoading: false,
      );
    }
  }

  Future<bool> signInWithEmail(String email, String password) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      if (FirebaseService.isInitialized) {
        final credential = await FirebaseAuth.instance
            .signInWithEmailAndPassword(
              email: email.trim(),
              password: password,
            );
        if (credential.user != null) {
          await _loadUserProfile(
            credential.user!.uid,
            credential.user!.email ?? email,
            credential.user!.displayName,
          );
          return true;
        }
      } else {
        // Fallback for local emulator / offline tests
        await Future.delayed(const Duration(milliseconds: 300));
        final profile = UserProfile(
          uid: 'user_${email.hashCode}',
          name: email.split('@').first,
          email: email.trim(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        state = AuthState(user: profile, isLoading: false);
        return true;
      }
      return false;
    } on FirebaseAuthException catch (e) {
      String userMessage = 'Authentication failed. Please try again.';
      if (e.code == 'user-not-found' ||
          e.code == 'wrong-password' ||
          e.code == 'invalid-credential') {
        userMessage = 'Invalid email or password. Please check and try again.';
      } else if (e.code == 'invalid-email') {
        userMessage = 'The email address is badly formatted.';
      } else if (e.code == 'user-disabled') {
        userMessage = 'This account has been disabled. Please contact support.';
      } else if (e.code == 'network-request-failed') {
        userMessage = 'Network error. Please verify your internet connection.';
      }
      state = state.copyWith(
        isLoading: false,
        error: AuthFailure(message: userMessage, code: e.code),
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: const UnknownFailure(
          message: 'An unexpected error occurred during sign in.',
        ),
      );
      return false;
    }
  }

  Future<bool> signUpWithEmail({
    required String name,
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      if (FirebaseService.isInitialized) {
        final credential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(
              email: email.trim(),
              password: password,
            );
        if (credential.user != null) {
          await credential.user!.updateDisplayName(name.trim());
          final uid = credential.user!.uid;
          final profile = UserProfile(
            uid: uid,
            name: name.trim(),
            email: email.trim(),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
          await FirebaseFirestore.instance.collection('users').doc(uid).set({
            'uid': uid,
            'name': name.trim(),
            'email': email.trim(),
            'photoUrl': null,
            'tripCount': 0,
            'distanceKm': 0,
            'memoryCount': 0,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          await AnalyticsService.logAccountCreated();
          state = AuthState(user: profile, isLoading: false);
          return true;
        }
      } else {
        await Future.delayed(const Duration(milliseconds: 300));
        final profile = UserProfile(
          uid: 'user_${DateTime.now().millisecondsSinceEpoch}',
          name: name.trim(),
          email: email.trim(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await AnalyticsService.logAccountCreated();
        state = AuthState(user: profile, isLoading: false);
        return true;
      }
      return false;
    } on FirebaseAuthException catch (e) {
      String userMessage = 'Registration failed. Please try again.';
      if (e.code == 'email-already-in-use') {
        userMessage = 'An account with this email already exists.';
      } else if (e.code == 'weak-password') {
        userMessage = 'Password is too weak. Please use at least 6 characters.';
      } else if (e.code == 'invalid-email') {
        userMessage = 'The email address is invalid.';
      }
      state = state.copyWith(
        isLoading: false,
        error: AuthFailure(message: userMessage, code: e.code),
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: const UnknownFailure(
          message: 'Could not complete registration. Please retry.',
        ),
      );
      return false;
    }
  }

  Future<void> sendPasswordReset(String email) async {
    if (FirebaseService.isInitialized) {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());
    }
  }

  Future<void> signOut() async {
    if (FirebaseService.isInitialized) {
      await FirebaseAuth.instance.signOut();
    }
    state = const AuthState(isLoading: false, user: null);
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
