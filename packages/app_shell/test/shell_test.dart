import 'package:app_shell/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('navigation uses host IDs and rejects ambiguous destinations', () {
    final nav = ShellNavigationController(['notes', 'activity', 'preferences']);
    addTearDown(nav.dispose);
    nav.selectId('preferences');
    expect(nav.selectedIndex, 2);
    expect(() => nav.selectId('library'), throwsArgumentError);
    expect(() => nav.select(9), throwsRangeError);
    expect(
      () => ShellNavigationController(['same', 'same']),
      throwsArgumentError,
    );
  });
  test('a host without a backend does not claim device capabilities', () async {
    final settings = ShellSettingsController(
      const MethodChannelShellPlatform(),
    );
    addTearDown(settings.dispose);
    await settings.load();
    expect(settings.ready, isTrue);
    expect(settings.supported, isFalse);
    expect(settings.lockEnabled, isFalse);
  });
  test('host notification IDs are independent of media categories', () {
    final settings = ShellSettingsController(
      const MethodChannelShellPlatform(),
      notificationCategoryIds: ['sync'],
    );
    addTearDown(settings.dispose);
    expect(settings.categories, {'sync': true});
    expect(
      () => ShellSettingsController(
        const MethodChannelShellPlatform(),
        notificationCategoryIds: [],
      ),
      throwsArgumentError,
    );
  });
  testWidgets(
    'standalone app loads packaged fonts and themes without host assets',
    (tester) async {
      await tester.runAsync(initializeAppShell);
      final settings = ShellSettingsController(
        const MethodChannelShellPlatform(),
      );
      await tester.runAsync(settings.load);
      await tester.pumpWidget(
        ShellApp(
          title: 'Notebook',
          settings: settings,
          home: const Scaffold(body: Text('Host content')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Host content'), findsOneWidget);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
        'Notebook',
      );
      expect(settings.themes.keys, containsAll(['retro', 'modern']));
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}
