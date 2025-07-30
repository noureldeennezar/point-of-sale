import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../Widget/OrdersTable.dart';
import '../Widget/home/home.dart';
import '../Widget/settings.dart';
import '../Widget/shifts/ShiftReportScreen.dart';
import '../cloud_services/AuthService.dart';
import 'BottomNavBar.dart';

class RootNavigator extends StatefulWidget {
  final String userName;
  final String loggedInUserName;

  const RootNavigator({
    super.key,
    required this.userName,
    required this.loggedInUserName,
  });

  @override
  _RootNavigatorState createState() => _RootNavigatorState();
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
    return StreamBuilder<Map<String, dynamic>?>(
      stream:
          Provider.of<AuthService>(context, listen: false).currentUserWithRole,
      builder: (context, snapshot) {
        String userRole = 'cashier';
        String userName = widget.userName;
        String loggedInUserName = widget.loggedInUserName;

        if (snapshot.hasData && snapshot.data != null) {
          userRole = snapshot.data!['role'] ?? 'cashier';
          userName = snapshot.data!['name'] ?? widget.userName;
          loggedInUserName =
              snapshot.data!['username'] ?? widget.loggedInUserName;
        }

        // Define the list of screens based on user role
        List<Widget> screens = [
          MyHomePage(
            title: 'Point of Sale',
            name: userName,
            loggedInUserName: loggedInUserName,
          ),
          const SettingsScreen(),
          const OrdersTable(),
        ];

        if (userRole == 'admin') {
          screens.add(const ShiftReportScreen());
        }

        return ValueListenableBuilder<int>(
          valueListenable: _selectedIndex,
          builder: (context, selectedIndex, child) {
            return Scaffold(
              body: IndexedStack(
                index: selectedIndex,
                children: screens,
              ),
              bottomNavigationBar: BottomNavBar(
                selectedIndex: selectedIndex,
                userName: userName,
                loggedInUserName: loggedInUserName,
                onItemTapped: (index) {
                  if (index < screens.length) {
                    _selectedIndex.value = index;
                  }
                },
              ),
            );
          },
        );
      },
    );
  }
}
