import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  AuthService() {
    _firestore.settings = const Settings(persistenceEnabled: true);
  }

  Stream<Map<String, dynamic>?> get currentUserWithRole {
    return _auth.authStateChanges().asyncMap((user) async {
      if (user == null) return null;
      final doc = await _firestore.collection('users').doc(user.uid).get();
      return doc.exists
          ? {
        'uid': user.uid,
        'email': user.email,
        'name': user.displayName,
        'role': doc['role'],
        'storeId': doc['storeId'], // Added
      }
          : null;
    });
  }

  Future<bool> validateStoreId(String storeId, {required bool isJoining}) async {
    final storeDoc = await _firestore.collection('stores').doc(storeId).get();
    return isJoining ? storeDoc.exists : !storeDoc.exists;
  }

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

  Future<bool> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<User?> signUp({
    required String email,
    required String password,
    required String name,
    required String role,
    required String storeId,
    required bool isJoiningStore,
  }) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await result.user!.updateDisplayName(name);
      await _firestore.collection('users').doc(result.user!.uid).set({
        'email': email,
        'displayName': name,
        'role': role,
        'storeId': storeId,
        'lastLogin': FieldValue.serverTimestamp(),
      });
      await _firestore.collection('stores').doc(storeId).collection('users').doc(result.user!.uid).set({
        'email': email,
        'displayName': name,
        'role': role,
      });
      if (!isJoiningStore) {
        await _firestore.collection('stores').doc(storeId).set({
          'storeId': storeId,
          'storeName': name + "'s Store", // Default name, can be customized
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      return result.user;
    } catch (e) {
      throw Exception('Failed to sign up: $e');
    }
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {}
  }

  Future<String?> getUserRole(String uid) async {
    try {
      DocumentSnapshot doc = await _firestore.collection('users').doc(uid).get();
      return doc.exists ? doc['role'] : null;
    } catch (e) {
      throw Exception('Failed to fetch user role: $e');
    }
  }

  Future<User?> createUser({
    required String email,
    required String password,
    required String name,
    required String role,
    required String storeId,
  }) async {
    return signUp(
      email: email,
      password: password,
      name: name,
      role: role,
      storeId: storeId,
      isJoiningStore: true,
    );
  }
}