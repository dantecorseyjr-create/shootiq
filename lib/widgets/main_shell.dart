import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/router/app_router.dart';

/// Bottom navigation shell wrapping authenticated dashboard pages.
class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.child});

  final Widget child;

  int _selectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith(AppRoutes.analyze) ||
        location.startsWith(AppRoutes.videoUpload) ||
        location.startsWith(AppRoutes.record) ||
        location.startsWith(AppRoutes.results) ||
        location.startsWith(AppRoutes.shotAiChat) ||
        location.startsWith(AppRoutes.movementDetail)) {
      return 1;
    }
    if (location.startsWith(AppRoutes.aiCoach) ||
        location.startsWith(AppRoutes.drills)) {
      return 2;
    }
    if (location.startsWith(AppRoutes.history)) return 3;
    if (location.startsWith(AppRoutes.profile) ||
        location.startsWith(AppRoutes.settings) ||
        location.startsWith(AppRoutes.editProfile)) {
      return 4;
    }
    if (location.startsWith(AppRoutes.dashboard) ||
        location.startsWith(AppRoutes.progress) ||
        location.startsWith(AppRoutes.sessionCompare)) {
      return 0;
    }
    return 0;
  }

  void _onTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go(AppRoutes.dashboard);
      case 1:
        context.go(AppRoutes.analyze);
      case 2:
        context.go(AppRoutes.aiCoach);
      case 3:
        context.go(AppRoutes.history);
      case 4:
        context.go(AppRoutes.profile);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ShootIQTheme.darkBackground,
      body: child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: ShootIQTheme.background,
          border: const Border(
            top: BorderSide(color: ShootIQTheme.cardBorder),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: BottomNavigationBar(
            currentIndex: _selectedIndex(context),
            onTap: (index) => _onTap(context, index),
            backgroundColor: ShootIQTheme.background,
            selectedItemColor: ShootIQTheme.primaryBlue,
            unselectedItemColor: ShootIQTheme.textSecondary,
            type: BottomNavigationBarType.fixed,
            elevation: 0,
            selectedFontSize: 11,
            unselectedFontSize: 11,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.home_outlined),
                activeIcon: Icon(Icons.home_rounded),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.videocam_outlined),
                activeIcon: Icon(Icons.videocam_rounded),
                label: 'Analyze',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.psychology_outlined),
                activeIcon: Icon(Icons.psychology_rounded),
                label: 'AI Coach',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.history_outlined),
                activeIcon: Icon(Icons.history_rounded),
                label: 'History',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person_outline_rounded),
                activeIcon: Icon(Icons.person_rounded),
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
