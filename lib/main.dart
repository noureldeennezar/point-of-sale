import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'Core/RootNavigator.dart';
import 'Core/app_localizations.dart';
import 'Core/theme_data.dart';
import 'Core/theme_provider.dart';
import 'Widget/auth/auth_provider.dart';
import 'Widget/auth/login.dart';
import 'Widget/splash_screen.dart';
import 'cloud_services/AuthService.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SQLite for desktop platforms
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Initialize Firebase safely for all platforms
  try {
    if (kIsWeb || Platform.isWindows || Platform.isMacOS) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
      debugPrint('✅ Firebase initialized (Web/Desktop)');
    } else {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      debugPrint('✅ Firebase initialized (Mobile)');
    }
  } catch (e) {
    debugPrint('❌ Firebase initialization failed: $e');
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocaleModel()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        Provider(create: (_) => AuthService()),
        // Add AuthProvider (depends on AuthService)
        ChangeNotifierProvider(
          create: (context) =>
              AuthProvider(Provider.of<AuthService>(context, listen: false)),
        ),
      ],
      child: const MyApp(),
    ),
  );

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<LocaleModel, ThemeProvider>(
      builder: (context, localeModel, themeProvider, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: localeModel.locale,
          supportedLocales: const [Locale('en', ''), Locale('ar', '')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          localeResolutionCallback: (locale, supportedLocales) {
            for (var supportedLocale in supportedLocales) {
              if (supportedLocale.languageCode == locale?.languageCode) {
                return supportedLocale;
              }
            }
            return supportedLocales.first;
          },
          builder: (context, child) {
            return Directionality(
              textDirection: localeModel.locale.languageCode == 'ar'
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              child: child!,
            );
          },
          title: AppLocalizations.of(context).translate('app_title'),
          theme: AppThemes.lightTheme,
          darkTheme: AppThemes.darkTheme,
          themeMode: themeProvider.themeMode,
          home: const AuthWrapper(), // ← Changed from SplashScreen
        );
      },
    );
  }
}

/// This widget handles the authentication state and decides which screen to show
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    return FutureBuilder(
      // We call initialize() and give it a tiny delay to allow smooth transition
      future: Future.wait([
        authProvider.initialize(),
        Future.delayed(const Duration(milliseconds: 400)), // smooth UX
      ]),
      builder: (context, snapshot) {
        // While initializing → show splash
        if (authProvider.isLoading ||
            snapshot.connectionState == ConnectionState.waiting) {
          return const SplashScreen();
        }

        // After initialization
        if (authProvider.currentUser != null) {
          // User is logged in (real user or guest)
          return RootNavigator();
        }

        // No user → go to login
        return const LoginScreen();
      },
    );
  }
}

class LocaleModel with ChangeNotifier {
  Locale _locale = const Locale('en', '');

  Locale get locale => _locale;

  void setLocale(Locale locale) {
    if (_locale != locale) {
      _locale = locale;
      notifyListeners();
    }
  }
}
