import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_pos/Core/theme_provider.dart';

import '../Core/app_localizations.dart'; // For translations

class ThemeSwitcher extends StatelessWidget {
  const ThemeSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    bool isDarkMode = themeProvider.themeMode == ThemeMode.dark;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          AppLocalizations.of(context).translate('dark_mode'),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        Switch(
          value: isDarkMode,
          onChanged: (value) {
            themeProvider.toggleTheme(value);
          },
        ),
      ],
    );
  }
}
