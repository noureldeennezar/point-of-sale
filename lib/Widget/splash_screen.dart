import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../Core/RootNavigator.dart';
import '../Widget/auth/auth_provider.dart';
import '../Widget/auth/login.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();

    // Start the navigation process
    _checkAuthAndNavigate();
  }

  Future<void> _checkAuthAndNavigate() async {
    // Enforce minimum splash time for good UX
    await Future.delayed(const Duration(seconds: 3));

    if (!mounted) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    // Always call initialize — it's safe and idempotent
    await authProvider.initialize();

    if (!mounted) return;

    // Navigate based on current user state
    if (authProvider.currentUser != null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const RootNavigator(),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const double maxLogoSize = 500.0;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: maxLogoSize,
                maxHeight: maxLogoSize,
              ),
              child: Image.asset(
                'assets/images/splash.png',
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 40),
            const CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 4,
            ),
          ],
        ),
      ),
    );
  }
} 
