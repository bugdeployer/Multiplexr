import 'package:multiplexr/src/bootstrap/settings_assembly.dart';
import 'package:multiplexr/src/core/platform/platform_transport.dart';
import 'package:app_shell/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/main.dart';
import 'package:multiplexr/src/platform_service.dart';

import 'fixtures/legacy_library_service.dart';

class EmptyLibraryTransport implements PlatformTransport {
  @override
  Future<T?> invokeMethod<T>(String method, [Object? arguments]) async =>
      method == 'readingSnapshot' ? '{}' as T : null;
  @override
  Future<Map<K, V>?> invokeMapMethod<K, V>(
    String method, [
    Object? arguments,
  ]) async => null;
}

class EmptyLibraryService extends LibraryService {
  EmptyLibraryService() : super(transport: EmptyLibraryTransport());
  @override
  Object get persistenceOwner => this;
  @override
  Future<Map<String, dynamic>> load() async => {
    'collections': [],
    'assets': [],
  };
}

class TestDevice extends PlatformService {
  final Map<String, dynamic> values = {
    'supported': true,
    'secureDevice': true,
    'biometric': true,
  };
  bool authenticated = true, permission = true;
  bool failSave = false;
  int authCalls = 0;
  @override
  Future<Map<String, dynamic>> load() async => Map.of(values);
  @override
  Future<void> save(Map<String, dynamic> data) async {
    if (failSave) throw Exception('storage failure');
    values.addAll(data);
  }

  @override
  Future<void> saveSecurity(Map<String, dynamic> data) async {
    if (failSave) throw Exception('storage failure');
    values.addAll(data);
  }

  @override
  Future<void> setCategory(String id, bool enabled) async {
    if (failSave) throw Exception('storage failure');
    values['category_$id'] = enabled;
  }

  @override
  Future<bool> authenticate() async {
    authCalls++;
    return authenticated;
  }

  @override
  Future<void> setLock(bool enabled) async {
    values['lockEnabled'] = enabled;
  }

  @override
  Future<bool> requestNotifications() async {
    values['notificationAllowed'] = permission;
    return permission;
  }

  @override
  Future<void> setNotifications(bool enabled) async {
    values['notifications'] = enabled;
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppThemeDefinition.loadBundled();
  });
  testWidgets('build info displays installed package values in settings', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      PlatformService.channel,
      (call) async => call.method == 'buildInfo'
          ? {
              'version': '2.3.4-preview',
              'build': '123',
              'package': 'app.test.installed',
            }
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        PlatformService.channel,
        null,
      ),
    );
    await tester.pumpWidget(
      MultiplexrApp(
        platform: TestDevice(),
        libraryService: EmptyLibraryService(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('SETTINGS'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Build info'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Build info'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Build info'));
    await tester.pumpAndSettle();
    expect(find.text('2.3.4-preview'), findsOneWidget);
    expect(find.text('123'), findsOneWidget);
    expect(find.text('app.test.installed'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });
  test(
    'appearance is independent, persisted and remembered per mode',
    () async {
      final device = TestDevice();
      final settings = createSettingsController(device);
      await settings.load();
      await settings.appearance(baseChoice: 2, accentChoice: 3);
      await settings.appearance(isDark: false);
      await settings.appearance(baseChoice: 4, accentChoice: 5);
      await settings.appearance(isDark: true);
      expect(settings.baseIndex, 2);
      expect(settings.accentIndex, 3);
      final restored = createSettingsController(device);
      await restored.load();
      expect(restored.dark, true);
      await restored.appearance(isDark: false);
      expect(restored.baseIndex, 4);
      expect(restored.accentIndex, 5);
      device.failSave = true;
      await expectLater(restored.appearance(baseChoice: 0), throwsException);
      expect(restored.baseIndex, 4);
    },
  );

  test('lock requires authentication, conceals, survives restart and fails closed on cancellation', () async {
    final device = TestDevice();
    final settings = createSettingsController(device);
    await settings.load();
    device.authenticated = false;
    expect(await settings.changeLock(true), false);
    expect(settings.lockEnabled, false);
    device.authenticated = true;
    expect(await settings.changeLock(true), true);
    settings.conceal();
    expect(settings.locked, true);
    device.authenticated = false;
    expect(await settings.unlock(), false);
    expect(settings.locked, true);
    expect(await settings.changeLock(false), false);
    expect(settings.lockEnabled, true);
    final restored = createSettingsController(device);
    await restored.load();
    expect(restored.locked, true);
    device.authenticated = true;
    expect(await restored.unlock(), true);
    expect(restored.locked, false);
  });

  test('notification denial never enables app notifications', () async {
    final device = TestDevice()..permission = false;
    final settings = createSettingsController(device);
    await settings.load();
    await settings.changeNotifications(true);
    expect(settings.notifications, false);
    device.permission = true;
    await settings.changeNotifications(true);
    expect(settings.notifications && settings.notificationAllowed, true);
    await settings.changeNotifications(false);
    expect(settings.notifications, false);
  });

  testWidgets(
    'empty destinations and appearance controls have no mock content',
    (tester) async {
      await tester.pumpWidget(
        MultiplexrApp(
          platform: TestDevice(),
          libraryService: EmptyLibraryService(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No collections'), findsOneWidget);
      expect(find.text('Cinema'), findsNothing);
      expect(find.text('BROWSE'), findsNothing);
      await tester.tap(find.text('SPACES'));
      await tester.pumpAndSettle();
      expect(find.text('Cinema'), findsOneWidget);
      expect(
        find.text('Include an unlocked Movies & TV collection to get started.'),
        findsOneWidget,
      );
      await tester.tap(find.text('SETTINGS'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Appearance'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Light'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('BONE'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('BONE'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('CHARCOAL'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('CHARCOAL'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cold launch with app lock hides all destinations', (
    tester,
  ) async {
    final device = TestDevice();
    device.values['lockEnabled'] = true;
    device.authenticated = false;
    await tester.pumpWidget(
      MultiplexrApp(platform: device, libraryService: EmptyLibraryService()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Multiplexr is locked'), findsOneWidget);
    expect(find.text('LIBRARY'), findsNothing);
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Multiplexr is locked'), findsOneWidget);
    device.authenticated = true;
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('No collections'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(find.text('Multiplexr is locked'), findsNothing);
    expect(find.text('No collections'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('No collections'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Multiplexr is locked'), findsOneWidget);
  });

  testWidgets('settings fit a narrow phone with large system text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MultiplexrApp(
        platform: TestDevice(),
        libraryService: EmptyLibraryService(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('SETTINGS'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Security'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Security'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Security'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('App lock'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
  });

  test(
    'system appearance follows brightness and saves layout and motion',
    () async {
      final device = TestDevice();
      final settings = createSettingsController(device);
      await settings.load();
      settings.systemBrightness(Brightness.light);
      await settings.preferences(system: true, dense: true, motion: true);
      expect(settings.dark, false);
      settings.systemBrightness(Brightness.dark);
      expect(settings.dark, true);
      await settings.preferences(system: false);
      settings.systemBrightness(Brightness.light);
      expect(settings.dark, true);
      final restored = createSettingsController(device);
      await restored.load();
      expect(restored.followSystem, false);
      expect(restored.dark, true);
      expect(restored.compact && restored.reduceMotion, true);
      device.failSave = true;
      await expectLater(restored.preferences(dense: false), throwsException);
      expect(restored.compact, true);
    },
  );

  test('lock delay covers immediately and expires without resetting on repeated lifecycle events', () async {
    var now = DateTime(2026, 10, 18);
    final device = TestDevice();
    device.values['lockEnabled'] = true;
    device.values['lockDelay'] = 30;
    final settings = createSettingsController(device, clock: () => now);
    await settings.load();
    expect(settings.locked, true);
    await settings.unlock();
    settings.background();
    expect(settings.covered, true);
    expect(settings.locked, false);
    now = now.add(const Duration(seconds: 20));
    settings.background();
    settings.foreground();
    expect(settings.locked || settings.covered, false);
    settings.background();
    now = now.add(const Duration(seconds: 30));
    settings.foreground();
    expect(settings.locked, true);
    await settings.unlock();
    settings.conceal();
    settings.foreground();
    expect(settings.locked, true); // Lock now overrides grace period.
  });

  test('security changes require authentication and survive restart', () async {
    final device = TestDevice();
    device.values['lockEnabled'] = true;
    final settings = createSettingsController(device);
    await settings.load();
    device.authenticated = false;
    expect(await settings.security(delay: 300, biometrics: false), false);
    expect(settings.lockDelay, 0);
    expect(settings.useBiometrics, true);
    device.authenticated = true;
    expect(
      await settings.security(
        delay: 60,
        biometrics: false,
        previews: false,
        screen: false,
      ),
      true,
    );
    final restored = createSettingsController(device);
    await restored.load();
    expect(restored.lockDelay, 60);
    expect(
      restored.useBiometrics || restored.hidePreviews || restored.protectScreen,
      false,
    );
    expect(restored.locked, true);
    device.failSave = true;
    await expectLater(restored.security(delay: 0), throwsException);
    expect(restored.lockDelay, 60);
  });

  test(
    'notification category preferences persist and respect save failures',
    () async {
      final device = TestDevice();
      final settings = createSettingsController(device);
      await settings.load();
      await settings.category('errors', false);
      final restored = createSettingsController(device);
      await restored.load();
      expect(restored.categories['errors'], false);
      expect(restored.categories['completed'], true);
      device.failSave = true;
      await expectLater(restored.category('errors', true), throwsException);
      expect(restored.categories['errors'], false);
    },
  );

  testWidgets('settings category navigation and back preserve the shell', (
    tester,
  ) async {
    await tester.pumpWidget(
      MultiplexrApp(
        platform: TestDevice(),
        libraryService: EmptyLibraryService(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('SETTINGS'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Notifications'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notifications'));
    await tester.pumpAndSettle();
    expect(find.text('Allow notifications'), findsOneWidget);
    expect(find.text('BASE COLOR'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsOneWidget);
    await tester.ensureVisible(find.text('Security'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Security'));
    await tester.pumpAndSettle();
    expect(find.text('App lock'), findsOneWidget);
    expect(find.text('Allow notifications'), findsNothing);
  });

  test('all base and accent combinations retain readable contrast', () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
    }

    final settings = createSettingsController(TestDevice());
    for (final dark in [true, false]) {
      settings.dark = dark;
      for (var base = 0; base < settings.bases.length; base++) {
        for (var accent = 0; accent < settings.accents.length; accent++) {
          if (dark) {
            settings.darkBase = base;
            settings.darkAccent = accent;
          } else {
            settings.lightBase = base;
            settings.lightAccent = accent;
          }
          final scheme = settings.theme.colorScheme;
          expect(
            contrast(settings.accent, settings.base),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrast(settings.accent, scheme.surface),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrast(scheme.onSurfaceVariant, scheme.surface),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrast(scheme.onPrimary, settings.accent),
            greaterThanOrEqualTo(4.5),
          );
        }
      }
    }
  });
}
