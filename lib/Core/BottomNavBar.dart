import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../cloud_services/AuthService.dart';
import 'app_localizations.dart';

class BottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final String userName;
  final String loggedInUserName;
  final Function(int) onItemTapped;

  const BottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.userName,
    required this.loggedInUserName,
    required this.onItemTapped,
  });

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return StreamBuilder<Map<String, dynamic>?>(
      stream:
          Provider.of<AuthService>(context, listen: false).currentUserWithRole,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              localizations.translate('error_loading_user_data'),
              style: theme.textTheme.bodyLarge,
            ),
          );
        }

        String? userRole = snapshot.data?['role'] ?? 'cashier';

        return NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onItemTapped,
          backgroundColor: theme.colorScheme.surface,
          indicatorColor: theme.colorScheme.primary.withOpacity(0.2),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.home_rounded),
              selectedIcon:
                  Icon(Icons.home_rounded, color: theme.colorScheme.primary),
              label: localizations.translate('Home'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.settings_rounded),
              selectedIcon: Icon(Icons.settings_rounded,
                  color: theme.colorScheme.primary),
              label: localizations.translate('settings'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.table_chart_rounded),
              selectedIcon: Icon(Icons.table_chart_rounded,
                  color: theme.colorScheme.primary),
              label: localizations.translate('order'),
            ),
            if (userRole == 'admin')
              NavigationDestination(
                icon: const Icon(Icons.access_time_filled_rounded),
                selectedIcon: Icon(Icons.access_time_filled_rounded,
                    color: theme.colorScheme.primary),
                label: localizations.translate('shifts'),
              ),
          ],
        );
      },
    );
  }
}
