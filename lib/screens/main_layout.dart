import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import 'devices_screen.dart';
import 'operations_screen.dart';
import 'overview_screen.dart';
import 'settings_screen.dart';

class MainLayout extends StatefulWidget {
  final int initialIndex;

  const MainLayout({
    super.key,
    this.initialIndex = 0,
  });

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  late int _currentIndex;
  StreamSubscription<InAppNotification>? _notifSub;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _notifSub =
        NotificationService.instance.inAppNotifications.listen(_showInAppBanner);
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    super.dispose();
  }

  void _showInAppBanner(InAppNotification notif) {
    if (!mounted) return;

    Color border = AppTheme.primaryOrange;
    IconData icon = Icons.info_outline;

    if (notif.type == 'disconnected') {
      border = Colors.redAccent;
      icon = Icons.link_off;
    } else if (notif.type == 'connected') {
      border = Colors.greenAccent;
      icon = Icons.check_circle_outline;
    } else if (notif.type == 'alert') {
      border = Colors.amberAccent;
      icon = Icons.warning_amber_rounded;
    }

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.modalBackground,
        elevation: 8,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(left: 16, right: 16, bottom: 90),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border, width: 1.5),
        ),
        duration: const Duration(seconds: 4),
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: border.withAlpha(30),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: border, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notif.title,
                    style: GoogleFonts.exo2(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    notif.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.exo2(
                      color: AppTheme.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onTabSelected(int index) {
    if (_currentIndex != index) {
      setState(() => _currentIndex = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      DevicesScreen(onNavigateTab: _onTabSelected),
      OverviewScreen(onNavigateTab: _onTabSelected),
      const OperationsScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          height: 72,
          margin: const EdgeInsets.only(left: 18, right: 18, bottom: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1B1C20),
            borderRadius: BorderRadius.circular(36),
            border: Border.all(
              color: AppTheme.darkBorder,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryOrange.withAlpha(25),
                blurRadius: 20,
                spreadRadius: 2,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: Colors.black.withAlpha(120),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = constraints.maxWidth / 4;

              return Stack(
                children: [
                  // Animated sliding pill background for active tab
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.fastOutSlowIn,
                    left: _currentIndex * itemWidth + (itemWidth - 68) / 2,
                    top: 6,
                    child: Container(
                      width: 68,
                      height: 58,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryOrange.withAlpha(35),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: AppTheme.primaryOrange.withAlpha(100),
                          width: 1.2,
                        ),
                      ),
                    ),
                  ),

                  // Tab Items
                  Row(
                    children: [
                      _buildAnimatedNavItem(
                        index: 0,
                        icon: Icons.smartphone_outlined,
                        activeIcon: Icons.smartphone,
                        label: 'Devices',
                        width: itemWidth,
                      ),
                      _buildAnimatedNavItem(
                        index: 1,
                        icon: Icons.receipt_long_outlined,
                        activeIcon: Icons.receipt_long,
                        label: 'Overview',
                        width: itemWidth,
                      ),
                      _buildAnimatedNavItem(
                        index: 2,
                        icon: Icons.account_tree_outlined,
                        activeIcon: Icons.account_tree,
                        label: 'Operations',
                        width: itemWidth,
                      ),
                      _buildAnimatedNavItem(
                        index: 3,
                        icon: Icons.settings_outlined,
                        activeIcon: Icons.settings,
                        label: 'Settings',
                        width: itemWidth,
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required double width,
  }) {
    final isSelected = _currentIndex == index;
    final color = isSelected ? AppTheme.primaryOrange : const Color(0xFF6E6F74);

    return SizedBox(
      width: width,
      height: 72,
      child: InkWell(
        onTap: () => _onTabSelected(index),
        borderRadius: BorderRadius.circular(36),
        splashColor: AppTheme.primaryOrange.withAlpha(40),
        highlightColor: Colors.transparent,
        child: AnimatedScale(
          scale: isSelected ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutBack,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, anim) => ScaleTransition(
                  scale: anim,
                  child: child,
                ),
                child: Icon(
                  isSelected ? activeIcon : icon,
                  key: ValueKey('${index}_$isSelected'),
                  color: color,
                  size: 24,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: GoogleFonts.exo2(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
