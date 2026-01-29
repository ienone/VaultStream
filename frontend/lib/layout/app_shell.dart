import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/layout/responsive_layout.dart';
import '../features/collection/providers/collection_filter_provider.dart';

class AppShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const AppShell({required this.navigationShell, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void onDestinationSelected(int index) {
      // Clear collection filters when leaving Library or resetting Library tab
      if (navigationShell.currentIndex == 1 || index == 1) {
        ref.read(collectionFilterProvider.notifier).clearFilters();
      }
      
      navigationShell.goBranch(
        index,
        initialLocation: index == navigationShell.currentIndex,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < ResponsiveLayout.mobileBreakpoint) {
          return _MobileShell(
            navigationShell: navigationShell,
            onDestinationSelected: onDestinationSelected,
          );
        } else {
          return _DesktopShell(
            navigationShell: navigationShell,
            onDestinationSelected: onDestinationSelected,
          );
        }
      },
    );
  }
}

class _MobileShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  final ValueChanged<int> onDestinationSelected;

  const _MobileShell({
    required this.navigationShell,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _AnimatedBranchContainer(
        currentIndex: navigationShell.currentIndex,
        child: navigationShell,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: onDestinationSelected,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.perm_media_outlined),
            selectedIcon: Icon(Icons.perm_media_rounded),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.rate_review_outlined),
            selectedIcon: Icon(Icons.rate_review_rounded),
            label: 'Review',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _DesktopShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  final ValueChanged<int> onDestinationSelected;

  const _DesktopShell({
    required this.navigationShell,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: onDestinationSelected,
            extended:
                MediaQuery.of(context).size.width >=
                ResponsiveLayout.desktopBreakpoint,
            minWidth: 80,
            minExtendedWidth: 200,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: AnimatedContainer(
                duration: 300.ms,
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.vape_free_rounded, // Replace with your logo icon
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard_rounded),
                label: Text('Dashboard'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.perm_media_outlined),
                selectedIcon: Icon(Icons.perm_media_rounded),
                label: Text('Library'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.rate_review_outlined),
                selectedIcon: Icon(Icons.rate_review_rounded),
                label: Text('Review'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings_rounded),
                label: Text('Settings'),
              ),
            ],
          ),
          VerticalDivider(
            thickness: 1,
            width: 1,
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: 0.2),
          ),
          Expanded(
            child: _AnimatedBranchContainer(
              currentIndex: navigationShell.currentIndex,
              child: navigationShell,
            ),
          ),
        ],
      ),
    );
  }
}

/// A wrapper that animates transitions between navigation branches.
class _AnimatedBranchContainer extends StatelessWidget {
  final int currentIndex;
  final Widget child;

  const _AnimatedBranchContainer({
    required this.currentIndex,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: 400.ms,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.02, 0), // Subtle horizontal slide
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: KeyedSubtree(
        key: ValueKey<int>(currentIndex),
        child: child,
      ),
    );
  }
}
