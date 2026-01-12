import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../cloud_services/AuthService.dart';
import '../../local_services/AuthDatabaseHelper.dart';

class UserModel {
  final String uid; // 'guest_local_user' for guests
  final String email;
  final String displayName;
  final String role;
  final String? storeId;
  final bool isGuest;

  UserModel({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    this.storeId,
    this.isGuest = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'user_id': uid,
      'email': email,
      'display_name': displayName,
      'role': role,
      'storeId': storeId,
      'is_active': 1,
      'is_guest': isGuest ? 1 : 0,
    };
  }

  factory UserModel.fromLocal(Map<String, dynamic> map) {
    return UserModel(
      uid: map['user_id'] as String,
      email: map['email'] as String? ?? 'unknown',
      displayName: map['display_name'] as String? ?? 'User',
      role: map['role'] as String? ?? 'cashier',
      storeId: map['storeId'] as String?,
      isGuest: (map['is_guest'] == 1) || (map['user_id'] == 'guest_local_user'),
    );
  }

  factory UserModel.fromFirebase(Map<String, dynamic> data) {
    return UserModel(
      uid: data['uid'] as String,
      email: data['email'] as String? ?? '',
      displayName: data['name'] as String? ?? 'User',
      role: data['role'] as String? ?? 'cashier',
      storeId: data['storeId'] as String?,
      isGuest: false,
    );
  }
}

class AuthProvider with ChangeNotifier {
  final AuthService _authService;
  UserModel? _currentUser;
  bool _isLoading = true;
  bool _isInitialized = false;

  AuthProvider(this._authService);

  UserModel? get currentUser => _currentUser;

  bool get isLoading => _isLoading;

  bool get isAuthenticated => _currentUser != null && !_currentUser!.isGuest;

  bool get isGuest => _currentUser?.isGuest == true;

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    _isLoading = true;
    notifyListeners();

    // 1. Fast path: check local active user first
    final localData = await DatabaseHelper.instance.getActiveUser();
    if (localData != null) {
      _currentUser = UserModel.fromLocal(localData);
      notifyListeners();
    }

    // 2. Then listen to Firebase (which may override local if real user)
    _authService.currentUserWithRole.listen((firebaseData) async {
      if (firebaseData != null) {
        // Real authenticated user from Firebase
        _currentUser = UserModel.fromFirebase(firebaseData);

        // Save/update local as active user
        await DatabaseHelper.instance.setActiveUser(_currentUser!.toMap());

        _isLoading = false;
        notifyListeners();
      } else {
        // Firebase says no user (logged out)
        // Keep guest if we had one, otherwise null
        if (_currentUser == null || !_currentUser!.isGuest) {
          _currentUser = null;
        }
        _isLoading = false;
        notifyListeners();
      }
    });
  }

  Future<void> signIn(String email, String password) async {
    try {
      final user = await _authService.signIn(email, password);
      if (user != null) {
        final role = await _authService.getUserRole(user.uid);
        if (role == null) throw Exception('Role not found');

        final firebaseData = {
          'uid': user.uid,
          'email': user.email,
          'name': user.displayName ?? email.split('@')[0],
          'role': role,
          // storeId will be fetched in currentUserWithRole stream
        };

        _currentUser = UserModel.fromFirebase(firebaseData);
        await DatabaseHelper.instance.setActiveUser(_currentUser!.toMap());

        notifyListeners();
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> continueAsGuest() async {
    await DatabaseHelper.instance.setGuestUser();

    _currentUser = UserModel(
      uid: 'guest_local_user',
      email: 'guest@localhost',
      displayName: 'Guest User',
      role: 'guest',
      isGuest: true,
    );

    notifyListeners();
  }

  Future<void> signOut() async {
    await _authService.signOut();
    await DatabaseHelper.instance.logoutLocal(); // deactivate local user
    _currentUser = null;
    notifyListeners();
  }
}

// Helper extension to access easily
extension AuthProviderExtension on BuildContext {
  AuthProvider get auth => read<AuthProvider>();
}
