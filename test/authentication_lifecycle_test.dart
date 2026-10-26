import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/main.dart';
import 'package:multiplexr/src/library/library_models.dart';
import 'package:app_shell/app_shell.dart';
import 'package:multiplexr/src/platform_service.dart';

import 'library_test.dart' show MemoryLibrary;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(AppThemeDefinition.loadBundled);
  for (final success in [true, false]) {
    testWidgets(
      'collection authentication ${success ? 'success avoids a second app unlock' : 'cancellation still fails closed'}',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final service = MemoryLibrary();
        service.collections.add(
          const VideoCollection(
            id: 'private',
            name: 'Private collection',
            subtype: VideoSubtype.videos,
            locked: true,
          ).toJson(),
        );
        var calls = 0;
        final auth = Completer<bool>();
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(PlatformService.channel, (
          call,
        ) async {
          if (call.method == 'load') {
            return {
              'supported': true,
              'lockEnabled': true,
              'secureDevice': true,
            };
          }
          if (call.method == 'authenticate') {
            if (++calls == 1) return true;
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.inactive,
            );
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.hidden,
            );
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.paused,
            );
            return auth.future;
          }
          return null;
        });
        addTearDown(() {
          messenger.setMockMethodCallHandler(PlatformService.channel, null);
        });
        await tester.pumpWidget(MultiplexrApp(libraryService: service));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Unlock').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Private collection'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Unlock collection'));
        await tester.pump();
        auth.complete(success);
        await tester.pump();
        expect(
          deviceAuthentication.active,
          true,
          reason: 'Native result may precede Android resume',
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(calls, 2);
        if (success) {
          expect(find.text('Multiplexr is locked'), findsNothing);
          expect(find.text('Collection locked'), findsNothing);
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          await tester.pump();
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pumpAndSettle();
          expect(
            find.text('Multiplexr is locked'),
            findsNothing,
            reason: 'Transient rotation/focus loss must not relock',
          );
          expect(find.text('Collection locked'), findsNothing);
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pumpAndSettle();
          expect(
            find.text('Multiplexr is locked'),
            findsWidgets,
            reason: 'A real app departure must still lock',
          );
        } else {
          expect(find.text('Multiplexr is locked'), findsWidgets);
        }
        await tester.pumpWidget(const SizedBox());
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      },
    );
  }
}
