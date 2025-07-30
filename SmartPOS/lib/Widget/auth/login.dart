import 'package:another_flushbar/flushbar.dart';
import 'package:flutter/material.dart';
import 'package:smart_pos/Widget/auth/signup.dart';

import '../../Core/RootNavigator.dart';
import '../../cloud_services/AuthService.dart';
import 'forgot_password.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool isVisible = false;
  bool _isLoading = false;
  final _authService = AuthService();
  final formKey = GlobalKey<FormState>();

  void _showErrorSnackBar(String message) {
    Flushbar(
      message: message,
      duration: const Duration(seconds: 3),
      backgroundColor: Theme.of(context).colorScheme.error,
      messageColor: Theme.of(context).colorScheme.onError,
      borderRadius: BorderRadius.circular(12),
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      animationDuration: const Duration(milliseconds: 300),
      flushbarPosition: FlushbarPosition.TOP,
      forwardAnimationCurve: Curves.easeOut,
      reverseAnimationCurve: Curves.easeIn,
      boxShadows: [
        BoxShadow(
          color: Colors.black.withOpacity(0.2),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ).show(context);
  }

  Future<void> login() async {
    if (formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });
      try {
        var user = await _authService.signIn(
          _emailController.text.trim(),
          _passwordController.text.trim(),
        );
        if (user != null && mounted) {
          String? role = await _authService.getUserRole(user.uid);
          if (role == null) {
            _showErrorSnackBar(
              ('Role not found'),
            );
            return;
          }
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (context) => RootNavigator(
                userName: user.displayName ?? _emailController.text,
                loggedInUserName: _emailController.text,
              ),
            ),
            (Route<dynamic> route) => false, // Clears all previous routes
          );
        } else {
          _showErrorSnackBar(
            ('Login failed'),
          );
        }
      } catch (e) {
        _showErrorSnackBar(
          ('Login failed'),
        );
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20.0, vertical: 40.0),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              color: theme.colorScheme.surfaceContainer,
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ('login'),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _emailController,
                        validator: (value) {
                          if (value!.isEmpty) return ('Email required');
                          if (!RegExp(r'^[\w-.]+@([\w-]+\.)+[\w-]{2,4}$')
                              .hasMatch(value)) {
                            return ('invalid Email');
                          }
                          return null;
                        },
                        decoration: InputDecoration(
                          labelText: ('Enter Email'),
                          labelStyle: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant),
                          prefixIcon: Icon(Icons.email,
                              color: theme.colorScheme.primary),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerLowest,
                          errorStyle: TextStyle(color: theme.colorScheme.error),
                        ),
                        style: TextStyle(color: theme.colorScheme.onSurface),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordController,
                        validator: (value) =>
                            value!.isEmpty ? ('Password required') : null,
                        obscureText: !isVisible,
                        decoration: InputDecoration(
                          labelText: ('Enter Password'),
                          labelStyle: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant),
                          prefixIcon: Icon(Icons.lock,
                              color: theme.colorScheme.primary),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerLowest,
                          suffixIcon: IconButton(
                            onPressed: () =>
                                setState(() => isVisible = !isVisible),
                            icon: Icon(
                              isVisible
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          errorStyle: TextStyle(color: theme.colorScheme.error),
                        ),
                        style: TextStyle(color: theme.colorScheme.onSurface),
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) =>
                                      const ForgotPasswordScreen()),
                            );
                          },
                          child: Text(
                            ('Forgot Password'),
                            style: TextStyle(color: theme.colorScheme.primary),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: theme.colorScheme.onPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                          child: _isLoading
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                )
                              : Text(
                                  ('Login'),
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onPrimary,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            ('Dont have an account ?'),
                            style:
                                TextStyle(color: theme.colorScheme.onSurface),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) => const SignUp()),
                              );
                            },
                            child: Text(
                              ('signup'),
                              style:
                                  TextStyle(color: theme.colorScheme.primary),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
