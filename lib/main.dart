import 'dart:async';

import 'package:ezy_cable_digi/core/services/connectivity_service.dart';
import 'package:ezy_cable_digi/core/services/error_handler_service.dart';
import 'package:ezy_cable_digi/core/services/session_timeout_service.dart';
import 'package:ezy_cable_digi/core/services/theme_service.dart';
import 'package:ezy_cable_digi/features/customers/customer_list_provider.dart';
import 'package:ezy_cable_digi/features/search/search_provider.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/login_screen.dart';
import 'core/services/notification_service.dart';

final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

/// D8: notifies only when a full SCREEN (PageRoute) is popped back to a
/// screen — never for dialogs, bottom sheets, pickers or dropdown menus
/// (those are PopupRoutes). The Dashboard uses it to reload its figures on
/// every return from another screen, like Android re-creating the fragment.
final RouteObserver<PageRoute<dynamic>> pageRouteObserver =
    RouteObserver<PageRoute<dynamic>>();

Future<void> mainEntry() async {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorHandlerService.init();
  await AppConfig.initDeviceImei();

  await runZonedGuarded(() async {
    await NotificationService.init();
    // Restore saved theme before the first frame
    await ThemeService.init();
    // Start connectivity listener for offline auto-sync
    ConnectivityService.instance.startListening();
    // Logout after 10+ minutes in the background (session only, no data reset)
    SessionTimeoutService.instance.start();
    runApp(const EzyCableDigiApp());
  }, (error, stack) {
    ErrorHandlerService.recordError(error, stack, reason: 'Uncaught app error');
  });
}

class EzyCableDigiApp extends StatelessWidget {
  const EzyCableDigiApp({super.key});

  @override
  Widget build(BuildContext context) {
    // MultiProvider sits above everything — providers survive full navigation.
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SearchProvider()),
        ChangeNotifierProvider(create: (_) => CustomerListProvider()),
      ],
      child: ListenableBuilder(
        listenable: ThemeService.instance,
        builder: (context, _) {
          final themeData = AppTheme.forIndex(ThemeService.instance.themeIndex)
              .copyWith(textTheme: GoogleFonts.interTextTheme());
          return MaterialApp(
            navigatorKey: rootNavigatorKey,
            scaffoldMessengerKey: rootMessengerKey,
            title: AppConfig.instance.appName,
            debugShowCheckedModeBanner: false,
            themeMode: ThemeMode.light,
            theme: themeData,
            navigatorObservers: [routeObserver, pageRouteObserver],
            home: const LoginScreen(),
          );
        },
      ),
    );
  }
}