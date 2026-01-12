import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../Widget/OrdersTable.dart';
import '../Widget/auth/auth_provider.dart';
import '../Widget/home/home.dart';
import '../Widget/settings.dart';
import '../Widget/shifts/ShiftReportScreen.dart';
import '../cloud_services/AuthService.dart';
import 'BottomNavBar.dart';

class RootNavigator extends StatefulWidget {
  const RootNavigator({super.key});

  @override
  State<RootNavigator> createState() => _RootNavigatorState();
}

class _RootNavigatorState extends State<RootNavigator> {
  final ValueNotifier<int> _selectedIndex = ValueNotifier<int>(0);

  @override
  void dispose() {
    _selectedIndex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (auth.currentUser == null) {
      return const Scaffold(body: Center(child: Text('No user found')));
    }

    final user = auth.currentUser!;
    final isGuest = user.isGuest;

    return StreamBuilder<Map<String, dynamic>?>(
      stream: Provider.of<AuthService>(
        context,
        listen: false,
      ).currentUserWithRole,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        String userRole = user.role;
        String displayName = user.displayName;
        String loggedInUserName = user.email;
        bool hasAdminAccess = (userRole == 'admin' || userRole == 'master');

        // For guest mode: force consistent values
        if (isGuest) {
          displayName = 'Guest User';
          loggedInUserName = 'guest@localhost';
          userRole = 'guest';
          hasAdminAccess = false;
        }
        // Only override with Firebase if real authenticated user
        else if (snapshot.hasData && snapshot.data != null) {
          final data = snapshot.data!;
          userRole = data['role'] ?? userRole;
          displayName = data['name'] ?? displayName;
          loggedInUserName = data['email'] ?? loggedInUserName;
          hasAdminAccess = userRole == 'admin' || userRole == 'master';
        }

        return _buildMainContent(
          userName: displayName,
          loggedInUserName: loggedInUserName,
          hasAdminAccess: hasAdminAccess,
          isGuest: isGuest,
        );
      },
    );
  }

  Widget _buildMainContent({
    required String userName,
    required String loggedInUserName,
    required bool hasAdminAccess,
    required bool isGuest,
  }) {
    final List<Widget> screens = [
      MyHomePage(
        title: 'Point of Sale',
        name: userName,
        loggedInUserName: loggedInUserName,
      ),
      const SettingsScreen(),
      const OrdersTable(),
    ];

    if (hasAdminAccess) {
      screens.add(const ShiftReportScreen());
    }

    return ValueListenableBuilder<int>(
      valueListenable: _selectedIndex,
      builder: (context, selectedIndex, child) {
        return Scaffold(
          body: IndexedStack(index: selectedIndex, children: screens),
          bottomNavigationBar: BottomNavBar(
            selectedIndex: selectedIndex,
            userName: userName,
            loggedInUserName: loggedInUserName,
            isGuest: isGuest,
            onItemTapped: (index) {
              if (index < screens.length) {
                _selectedIndex.value = index;
              } else {
                _selectedIndex.value = 0;
              }
            },
          ),
        );
      },
    );
  }
}
