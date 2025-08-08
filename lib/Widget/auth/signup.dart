import 'package:another_flushbar/flushbar.dart';
import 'package:flutter/material.dart';
import '../../Core/RootNavigator.dart';
import '../../cloud_services/AuthService.dart';
import 'login.dart';

class SignUp extends StatefulWidget {
  const SignUp({super.key});

  @override
  State<SignUp> createState() => _SignUpState();
}

class _SignUpState extends State<SignUp> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nameController = TextEditingController();
  final _storeIdController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool isVisible = false;
  bool _isLoading = false;
  bool _isJoiningStore = true;
  final _authService = AuthService();
  String? _selectedRole = 'cashier';

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

  Future<void> signUp() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });
      try {
        bool isStoreValid = await _authService.validateStoreId(
          _storeIdController.text.trim(),
          isJoining: _isJoiningStore,
        );
        if (!isStoreValid) {
          _showErrorSnackBar(_isJoiningStore
              ? 'Invalid Store ID'
              : 'Store ID already exists');
          return;
        }

        var user = await _authService.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
          name: _nameController.text.trim(),
          role: _selectedRole!,
          storeId: _storeIdController.text.trim(),
          isJoiningStore: _isJoiningStore,
        );
        if (user != null && mounted) {
          var signedInUser = await _authService.signIn(
            _emailController.text.trim(),
            _passwordController.text.trim(),
          );
          if (signedInUser != null && mounted) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (context) => RootNavigator(
                  userName: signedInUser.displayName ?? _emailController.text,
                  loggedInUserName: _emailController.text,
                ),
              ),
                  (Route<dynamic> route) => false,
            );
          } else {
            _showErrorSnackBar('Login failed');
          }
        } else {
          _showErrorSnackBar('Signup failed');
        }
      } catch (e) {
        _showErrorSnackBar('Signup failed: $e');
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
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 40.0),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              color: theme.colorScheme.surfaceContainer,
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Register account',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _nameController,
                        validator: (value) =>
                        value!.isEmpty ? 'Name required' : null,
                        decoration: InputDecoration(
                          labelText: 'Enter Name',
                          labelStyle: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant),
                          prefixIcon:
                          Icon(Icons.person, color: theme.colorScheme.primary),
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
                        controller: _emailController,
                        validator: (value) {
                          if (value!.isEmpty) return 'Email required';
                          if (!RegExp(r'^[\w-.]+@([\w-]+\.)+[\w-]{2,4}$')
                              .hasMatch(value)) {
                            return 'Invalid Email';
                          }
                          return null;
                        },
                        decoration: InputDecoration(
                          labelText: 'Enter Email',
                          labelStyle: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant),
                          prefixIcon:
                          Icon(Icons.email, color: theme.colorScheme.primary),
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
                        validator: (value) {
                          if (value!.isEmpty) return 'Password required';
                          if (value.length < 6) return 'Password too short';
                          return null;
                        },
                        obscureText: !isVisible,
                        decoration: InputDecoration(
                          labelText: 'Enter Password',
                          labelStyle: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant),
                          prefixIcon:
                          Icon(Icons.lock, color: theme.colorScheme.primary),
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
                      TextFormField(
                        controller: _confirmPasswordController,
                        validator: (value) {
                          if (value!.isEmpty) return 'Password required';
                          if (value != _passwordController.text) {
                            return 'Password mismatch';
                          }
                          return null;
                        },
                        obscureText: !isVisible,
                        decoration: InputDecoration(
                          labelText: 'Confirm Password',
                          labelStyle: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant),
                          prefixIcon:
                          Icon(Icons.lock, color: theme.colorScheme.primary),
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
                      DropdownButtonFormField<String>(
                        value: _selectedRole,
                        items: const [
                          DropdownMenuItem(value: 'cashier', child: Text('Cashier')),
                          DropdownMenuItem(value: 'admin', child: Text('Admin')),
                        ],
                        onChanged: (value) =>
                            setState(() => _selectedRole = value),
                        decoration: InputDecoration(
                          labelText: 'Select Role',
                          labelStyle: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant),
                          prefixIcon:
                          Icon(Icons.group, color: theme.colorScheme.primary),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerLowest,
                          errorStyle: TextStyle(color: theme.colorScheme.error),
                        ),
                        style: TextStyle(color: theme.colorScheme.onSurface),
                        validator: (value) => value == null ? 'Role required' : null,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          Radio<bool>(
                            value: true,
                            groupValue: _isJoiningStore,
                            onChanged: (value) =>
                                setState(() => _isJoiningStore = value!),
                            activeColor: theme.colorScheme.primary,
                          ),
                          Text('Join Existing Store',
                              style:
                              TextStyle(color: theme.colorScheme.onSurface)),
                          Radio<bool>(
                            value: false,
                            groupValue: _isJoiningStore,
                            onChanged: (value) =>
                                setState(() => _isJoiningStore = value!),
                            activeColor: theme.colorScheme.primary,
                          ),
                          Text('Create New Store',
                              style:
                              TextStyle(color: theme.colorScheme.onSurface)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _storeIdController,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Store ID required';
                          }
                          return null;
                        },
                        decoration: InputDecoration(
                          labelText: _isJoiningStore
                              ? 'Enter Store ID'
                              : 'New Store ID',
                          labelStyle: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant),
                          prefixIcon:
                          Icon(Icons.store, color: theme.colorScheme.primary),
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
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : signUp,
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
                            'Signup',
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
                            'Already have an account?',
                            style:
                            TextStyle(color: theme.colorScheme.onSurface),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) => const LoginScreen()),
                              );
                            },
                            child: Text(
                              'Login',
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
    _confirmPasswordController.dispose();
    _nameController.dispose();
    _storeIdController.dispose();
    super.dispose();
  }
}