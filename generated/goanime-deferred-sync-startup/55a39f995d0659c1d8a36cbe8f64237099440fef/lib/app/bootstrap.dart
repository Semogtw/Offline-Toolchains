// ignore_for_file: unawaited_futures
// Existing callbacks/fixtures still rely on implicit async or dynamic JSON shapes; keep new strict rules enabled elsewhere.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/app_startup_service.dart';
import '../services/availability_service.dart';
import '../services/crash_reporting_service.dart';
import '../services/download_service.dart';
import '../services/locale_service.dart';
import '../services/mal_provider_availability_service.dart';
import '../services/platform_services.dart';
import '../services/runtime_database_update_service.dart';
import '../services/theme_service.dart';
import '../services/update_service.dart';
import '../services/user_sync_service.dart';
import '../utils/performance_config.dart';
import 'app.dart';

Future<void> bootstrapGoAnimeApp() async {
  WidgetsFlutterBinding.ensureInitialized();

  final crashReportingService = CrashReportingService.instance;
  await crashReportingService.initialize();
  crashReportingService.installGlobalErrorHandlers();

  await initializePlatformServices();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(goAnimeSystemUiOverlayStyle());

  PerformanceConfig.init();
  WidgetsBinding.instance.addObserver(_ImageCacheMemoryPressureObserver());

  final downloadService = DownloadService();
  final updateService = UpdateService();
  final userSyncService = UserSyncService.instance;
  await userSyncService.initialize(deferAnonymousSignIn: true);
  final settingsSyncWriter = userSyncService.recordSettings;

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => LocaleService(settingsSyncWriter: settingsSyncWriter),
        ),
        ChangeNotifierProvider(
          create: (_) => ThemeService(settingsSyncWriter: settingsSyncWriter),
        ),
        ChangeNotifierProvider.value(value: userSyncService),
        ChangeNotifierProvider.value(value: downloadService),
        ChangeNotifierProvider.value(value: updateService),
      ],
      child: MyApp(),
    ),
  );

  startDeferredStartupServices(initializeDownloads: downloadService.initialize);
  unawaited(_updateRuntimeDatabasesAndReloadAvailability());
  updateService.startBackgroundCheck();
}

Future<void> _updateRuntimeDatabasesAndReloadAvailability() async {
  try {
    // Share the deferred initialization future before an updater can close and
    // replace the active SQLite connection.
    await AvailabilityService.initialize();
    final result = await RuntimeDatabaseUpdateService().updateIfNeeded();
    if (result == RuntimeDatabaseUpdateResult.updated) {
      await AvailabilityService.reload();
    }
    await MalProviderAvailabilityService.refreshConfiguredFromNetwork();
  } catch (error, stackTrace) {
    debugPrint('[Bootstrap] Runtime catalog update failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}

class _ImageCacheMemoryPressureObserver extends WidgetsBindingObserver {
  @override
  void didHaveMemoryPressure() {
    PerformanceConfig.clearImageCache();
  }
}
