import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Core/RootNavigator.dart';
import '../Widget/auth/auth_provider.dart';
import '../Widget/auth/login.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const String _firstTimeKey = 'is_first_time_open';
  static const String _correctCode = '224003';

  @override
  void initState() {
    super.initState();
    _checkAuthAndNavigate();
  }

  Future<void> _checkAuthAndNavigate() async {
    await Future.delayed(const Duration(seconds: 2)); // reduced a bit

    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    // Always safe to call
    await authProvider.initialize();

    if (!mounted) return;

    final bool isFirstTime = prefs.getBool(_firstTimeKey) ?? true;

    if (isFirstTime) {
      // Show security code screen
      if (!mounted) return;
      final bool? success = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const _FirstTimeSecurityScreen(code: _correctCode),
        ),
      );

      if (success != true) {
        // User canceled or wrong code too many times → exit app
        if (mounted) {
          Navigator.of(context).pop(); // or SystemNavigator.pop();
        }
        return;
      }

      // Mark as no longer first time
      await prefs.setBool(_firstTimeKey, false);
    }

    // Normal navigation flow
    if (!mounted) return;

    if (authProvider.currentUser != null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const RootNavigator()),
      );
    } else {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
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

// ──────────────────────────────────────────────────────────────

class _FirstTimeSecurityScreen extends StatefulWidget {
  final String code;

  const _FirstTimeSecurityScreen({required this.code});

  @override
  State<_FirstTimeSecurityScreen> createState() =>
      _FirstTimeSecurityScreenState();
}

class _FirstTimeSecurityScreenState extends State<_FirstTimeSecurityScreen> {
  final _controller = TextEditingController();
  String? _errorText;
  int _attempts = 0;
  static const int _maxAttempts = 5;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _checkCode() async {
    final input = _controller.text.trim();

    if (input == widget.code) {
      Navigator.pop(context, true);
      return;
    }

    setState(() {
      _attempts++;
      _errorText = 'Wrong code. Attempts: $_attempts/$_maxAttempts';
    });

    if (_attempts >= _maxAttempts) {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        Navigator.pop(context, false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.security, size: 80, color: Colors.white70),
              const SizedBox(height: 32),
              const Text(
                "First Time Security Check",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "Enter the code to continue",
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 40),
              TextField(
                controller: _controller,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 32,
                  letterSpacing: 16,
                  color: Colors.white,
                ),
                decoration: InputDecoration(
                  counterText: "",
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.1),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  errorText: _errorText,
                  errorStyle: const TextStyle(color: Colors.orangeAccent),
                ),
                onSubmitted: (_) => _checkCode(),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _checkCode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    "VERIFY",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  "Cancel",
                  style: TextStyle(color: Colors.white60),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
