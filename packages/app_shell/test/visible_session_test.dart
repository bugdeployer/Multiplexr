import 'package:app_shell/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class VisibleSettings extends ShellSettingsController {
  VisibleSettings() : super(const MethodChannelShellPlatform());
  bool visible = false;
  @override
  bool get visibleSession => visible;
}

void main() {
  test('visible session preserves an authorized session but never unlocks a locked app', () {
    final s = VisibleSettings()
      ..lockEnabled = true
      ..visible = true;
    addTearDown(s.dispose);
    s.obscure();
    s.background();
    expect(s.locked, isFalse);
    expect(s.covered, isFalse);
    s.locked = true;
    s.background();
    expect(s.locked, isTrue);
    s.locked = false;
    s.visible = false;
    s.background();
    expect(s.locked, isTrue);
  });
  testWidgets('temporary privacy cover does not pretend app is locked', (
    tester,
  ) async {
    final s = VisibleSettings()
      ..ready = true
      ..covered = true;
    await tester.pumpWidget(
      MaterialApp(
        home: AppLockLayer(
          settings: s,
          appName: 'Notebook',
          child: const Text('Private content'),
        ),
      ),
    );
    expect(find.text('Notebook is locked'), findsNothing);
    expect(find.text('Unlock'), findsNothing);
    expect(find.text('Private content'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    s.dispose();
  });
}
