// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'core/app_config.dart';
import 'core/auth_service.dart';
import 'core/navigation_service.dart';
import 'core/connectivity_service.dart';
import 'core/permission_service.dart';
import 'core/location_service.dart';
import 'pages/splash_page.dart';
import 'pages/login_page.dart';
import 'pages/production_page.dart';
import 'pages/sales_page.dart';
import 'pages/reports_menu_page.dart';
import 'controllers/production_controller.dart';
import 'pages/shared_widgets.dart';
import 'pages/help_page.dart';
import 'pages/anomaly_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  Get.put(ConnectivityService());
  Get.put(NavigationService());
  runApp(const DairyApp());
}

class DairyApp extends StatelessWidget {
  const DairyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Dairy Management',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: kNavy),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
          ),
        ),
      ),
      builder: (context, child) {
        return Container(
          color: const Color(AppConfig.surroundColorHex),
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppConfig.maxAppWidth),
            child: child!,
          ),
        );
      },
      initialRoute: '/',
      getPages: [
        GetPage(name: '/',      page: () => const SplashPage()),
        GetPage(name: '/login', page: () => const LoginPage()),
        GetPage(name: '/home',  page: () => const AppShell(),
            middlewares: [_AuthGuard()]),
      ],
    );
  }
}

// ── Auth guard ─────────────────────────────────────────────

class _AuthGuard extends GetMiddleware {
  @override
  RouteSettings? redirect(String? route) {
    if (!AuthService.instance.isLoggedIn) {
      return const RouteSettings(name: '/login');
    }
    return null;
  }
}

// ── Page registry ──────────────────────────────────────────
// Single place that maps page keys (from server) to widgets + nav config.
// To add a new page: add one entry here. Nothing else changes.

class _PageDef {
  final String       key;
  final Widget       page;
  final String       label;
  final IconData     icon;
  final IconData     activeIcon;

  const _PageDef({
    required this.key,
    required this.page,
    required this.label,
    required this.icon,
    required this.activeIcon,
  });
}

const List<_PageDef> _allPages = [
  _PageDef(
    key:        'production',
    page:       ProductionPage(),
    label:      'Production',
    icon:       Icons.factory_outlined,
    activeIcon: Icons.factory,
  ),
  _PageDef(
    key:        'sales',
    page:       SalesPage(),
    label:      'Sales',
    icon:       Icons.store_outlined,
    activeIcon: Icons.store,
  ),
  _PageDef(
    key:        'reports',
    page:       ReportsMenuPage(),
    label:      'Reports',
    icon:       Icons.assessment_outlined,
    activeIcon: Icons.assessment,
  ),
  _PageDef(
    key:        'anomalies',
    page:       AnomalyPage(),
    label:      'Anomalies',
    icon:       Icons.warning_amber_outlined,
    activeIcon: Icons.warning_amber,
  ),
];

// ── App shell ──────────────────────────────────────────────

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _idx = 0;

  @override
  void initState() {
    super.initState();
    // Permissions are already loaded at this point (AppShell is behind _AuthGuard).
    // Initialise the global location so every controller has a value immediately.
    LocationService.instance.init();
  }

  // Build the visible page list from what the server granted
  List<_PageDef> get _visiblePages {
    final granted = PermissionService.instance.pages;
    return _allPages.where((p) => granted.contains(p.key)).toList();
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: kNavy, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      LocationService.instance.clear();
      await AuthService.instance.logout();
      Get.offAllNamed('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user  = AuthService.instance.currentUser;
    final pages = _visiblePages;

    // Guard: if server grants no pages, show a clear message
    if (pages.isEmpty) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.lock_outline, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('No access assigned',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text(
                'Your account has not been assigned to any location yet.\nPlease contact your administrator.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: () async {
                  await AuthService.instance.logout();
                  Get.offAllNamed('/login');
                },
                child: const Text('Sign Out'),
              ),
            ]),
          ),
        ),
      );
    }

    // Clamp index in case permissions changed and current tab is now gone
    final safeIdx = _idx.clamp(0, pages.length - 1);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: kNavy,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        title: Row(children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Icon(Icons.water_drop_outlined,
                size: 16, color: Colors.white),
          ),
          const SizedBox(width: 8),
          // Global location picker — writes to LocationService, all pages react
          Obx(() {
            final locs = LocationService.instance.locations;
            final sel  = LocationService.instance.selected.value;
            if (locs.length <= 1) {
              // Single location: just show the name, no dropdown needed
              return Text(sel?.name ?? pages[safeIdx].label,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700));
            }
            return DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: sel?.id,
                dropdownColor: kNavy,
                iconEnabledColor: Colors.white,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700),
                items: locs.map((l) => DropdownMenuItem(
                  value: l.id,
                  child: Text(l.name,
                      style: const TextStyle(color: Colors.white)),
                )).toList(),
                onChanged: (id) {
                  LocationService.instance.select(id);
                },
              ),
            );
          }),
        ]),
        actions: [
          PopupMenuButton<String>(
            offset: const Offset(0, 48),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            icon: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.person_outline, size: 16, color: Colors.white),
                const SizedBox(width: 6),
                Text(user?.label ?? 'User',
                    style: const TextStyle(color: Colors.white,
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down, size: 16, color: Colors.white),
              ]),
            ),
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user?.label ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w700,
                              fontSize: 14, color: Color(0xFF2C3E50))),
                      if (user?.email?.isNotEmpty == true)
                        Text(user!.email!,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey)),
                      const Divider(height: 16),
                    ]),
              ),
              const PopupMenuItem(
                value: 'help',
                child: Row(children: [
                  Icon(Icons.help_outline_rounded, size: 18, color: kNavy),
                  SizedBox(width: 10),
                  Text('Help & Guide',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ]),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(children: [
                  Icon(Icons.logout_outlined, size: 18, color: kRed),
                  SizedBox(width: 10),
                  Text('Sign Out',
                      style: TextStyle(
                          color: kRed, fontWeight: FontWeight.w600)),
                ]),
              ),
            ],
            onSelected: (v) {
              if (v == 'logout') _logout();
              if (v == 'help') { Get.to(() => const HelpPage(),
                  transition: Transition.rightToLeft); }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Obx(() {
        // React to navigation jump requests (e.g. stock row → production tab)
        final req = NavigationService.instance.jumpRequest.value;
        if (req != null) {
          final targetIdx = pages.indexWhere((p) => p.key == req.pageKey);
          if (targetIdx != -1) {
            // Schedule state + date update after this build frame
            WidgetsBinding.instance.addPostFrameCallback((_) {
              setState(() => _idx = targetIdx);
              // Set date on ProductionController — it is now mounted because
              // IndexedStack keeps all pages alive once visited, but if this
              // is the first visit Get.put() inside ProductionPage will have
              // just run. Either way we can find it after the frame.
              if (req.date != null && req.pageKey == 'production') {
                final prodCtrl = Get.isRegistered<ProductionController>()
                    ? Get.find<ProductionController>()
                    : null;
                prodCtrl?.entryDate.value = req.date!;
              }
              NavigationService.instance.jumpRequest.value = null;
            });
          }
        }
        return Column(children: [
          const OfflineBanner(),
          Expanded(
            child: IndexedStack(
              index: safeIdx,
              children: pages.map((p) => p.page).toList(),
            ),
          ),
        ]);
      }),
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeIdx,
        onDestinationSelected: (i) {
          setState(() => _idx = i);
        },
        indicatorColor: kNavy.withValues(alpha: 0.12),
        destinations: pages.map((p) => NavigationDestination(
          icon:         Icon(p.icon),
          selectedIcon: Icon(p.activeIcon, color: kNavy),
          label:        p.label,
        )).toList(),
      ),
    );
  }
}
