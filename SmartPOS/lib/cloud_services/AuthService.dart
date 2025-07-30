import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  AuthService() {
    _firestore.settings = const Settings(persistenceEnabled: true);
  }

  // Stream for current user with role
  Stream<Map<String, dynamic>?> get currentUserWithRole {
    return _auth.authStateChanges().asyncMap((user) async {
      if (user == null) return null;
      final doc = await _firestore.collection('users').doc(user.uid).get();
      return doc.exists
          ? {
        'uid': user.uid,
        'email': user.email,
        'name': user.displayName,
        'role': doc['role']
      }
          : null;
    });
  }

  // Login with email and password
  Future<User?> signIn(String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      await _firestore.collection('users').doc(result.user!.uid).update({
        'lastLogin': FieldValue.serverTimestamp(),
      });
      return result.user;
    } catch (e) {
      throw Exception('Failed to sign in: $e');
    }
  }

  // Send password reset email
  Future<bool> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return true;
    } catch (e) {
      return false;
    }
  }

  // Sign up with email, password, name, and role
  Future<User?> signUp({
    required String email,
    required String password,
    required String name,
    required String role,
  }) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      // Disable email verification
      // await result.user!.sendEmailVerification(); // Removed
      await result.user!.updateDisplayName(name);
      await _firestore.collection('users').doc(result.user!.uid).set({
        'email': email,
        'displayName': name,
        'role': role,
        'lastLogin': FieldValue.serverTimestamp(),
      });
      return result.user;
    } catch (e) {
      throw Exception('Failed to sign up: $e');
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {}
  }

  // Get user role
  Future<String?> getUserRole(String uid) async {
    try {
      DocumentSnapshot doc =
      await _firestore.collection('users').doc(uid).get();
      return doc.exists ? doc['role'] : null;
    } catch (e) {
      throw Exception('Failed to fetch user role: $e');
    }
  }

  // Create user (admin-only)
  Future<User?> createUser({
    required String email,
    required String password,
    required String name,
    required String role,
  }) async {
    return signUp(email: email, password: password, name: name, role: role);
  }
}
