import 'package:multiplexr/src/bootstrap/library_assembly.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/settings/domain/media_settings.dart';
import 'package:multiplexr/src/experience/actions/media_actions.dart';
import 'package:multiplexr/src/experience/navigation/opening_policy.dart';
import 'package:multiplexr/src/experience/navigation/navigation_coordinator.dart';
import 'package:multiplexr/src/catalog/domain/classification.dart';
import 'package:multiplexr/src/media/navigation_settings.dart';
import 'package:multiplexr/src/media/video_navigation.dart';
import 'package:multiplexr/src/media/video_projections.dart';
import 'package:multiplexr/src/library/library_models.dart';

import 'media_foundation_test.dart' show SharedStore;

void main() {
  const resolver = SettingsResolver();
  test('typed inheritance resolves app collection ancestors title and records origin', () {
    final layers = [
      SettingsLayer(SettingsScope.app, 'app', {
        'rate': const SettingOverride.value(1.25),
      }),
      SettingsLayer(SettingsScope.collection, 'c', {
        'rate': const SettingOverride.value(1.5),
      }),
      SettingsLayer(SettingsScope.group, 'series', {
        'rate': const SettingOverride.value(1.75),
      }),
      SettingsLayer(SettingsScope.group, 'season', {
        'rate': const SettingOverride.inherit(),
      }),
      SettingsLayer(SettingsScope.title, 't', {
        'rate': const SettingOverride.value(2.0),
      }),
    ];
    final result = resolver.resolve(MediaSettings.rate, layers);
    expect(result.value, 2);
    expect(result.scope, SettingsScope.title);
    expect(result.sourceId, 't');
    final inherited = resolver.resolve(MediaSettings.rate, layers.take(4));
    expect(inherited.value, 1.75);
    expect(inherited.sourceId, 'series');
  });
  test('false is an override and invalid scope type rate or parent order is rejected', () {
    expect(
      resolver.resolve(MediaSettings.autoplayNext, [
        SettingsLayer(SettingsScope.app, 'app', {
          'autoplayNext': const SettingOverride.value(true),
        }),
        SettingsLayer(SettingsScope.collection, 'c', {
          'autoplayNext': const SettingOverride.value(false),
        }),
      ]).value,
      false,
    );
    expect(
      () => resolver.resolve(MediaSettings.engine, [
        SettingsLayer(SettingsScope.title, 't', {
          'engine': const SettingOverride.value(EngineSelection.external),
        }),
      ]),
      throwsArgumentError,
    );
    expect(
      () => resolver.resolve(MediaSettings.rate, [
        SettingsLayer(SettingsScope.title, 't', {
          'rate': const SettingOverride.value(double.nan),
        }),
      ]),
      throwsArgumentError,
    );
    expect(
      () => resolver.resolve(MediaSettings.rate, [
        SettingsLayer(SettingsScope.title, 't', {
          'rate': const SettingOverride.value('fast'),
        }),
      ]),
      throwsArgumentError,
    );
    expect(
      () => resolver.resolve(MediaSettings.rate, [
        SettingsLayer(SettingsScope.title, 't', {}),
        SettingsLayer(SettingsScope.collection, 'c', {}),
      ]),
      throwsArgumentError,
    );
  });
  test('opening policy preserves group explicit-play unavailable and privacy semantics', () {
    const policy = OpeningPolicy();
    expect(
      policy.resolve(
        group: true,
        action: TitleOpenAction.play,
        explicitPlay: true,
      ),
      OpeningDestination.contents,
    );
    expect(
      policy.resolve(
        group: false,
        action: TitleOpenAction.details,
        explicitPlay: true,
      ),
      OpeningDestination.session,
    );
    expect(
      policy.resolve(
        group: false,
        action: TitleOpenAction.details,
        available: false,
      ),
      OpeningDestination.details,
    );
    expect(
      policy.resolve(
        group: false,
        action: TitleOpenAction.play,
        available: false,
      ),
      OpeningDestination.unavailable,
    );
    expect(
      policy.resolve(
        group: true,
        action: TitleOpenAction.play,
        authorized: false,
      ),
      OpeningDestination.denied,
    );
    for (final legacy in [false, true]) {
      final collection = const VideoCollection(
        id: 'c',
        name: 'c',
        subtype: VideoSubtype.cinema,
      );
      expect(collection.opensDetails(legacy: legacy), legacy);
    }
  });
  test('action registry preserves order and rechecks access and capabilities at execution', () async {
    expect(MediaActionRegistry.definitions.map((d) => d.label), [
      'Settings',
      'Edit metadata',
      'Choose artwork',
      'Find metadata online',
    ]);
    var authorized = true, called = false;
    MediaActionContext current() => MediaActionContext(
      authorized: authorized,
      capabilities: const {MediaCapability.artwork},
      hasSettings: true,
    );
    expect(
      MediaActionRegistry.permitted(MediaActionId.chooseArtwork, current()),
      true,
    );
    expect(
      MediaActionRegistry.permitted(MediaActionId.findMetadata, current()),
      false,
    );
    authorized = false;
    await expectLater(
      MediaActionRegistry.execute(
        MediaActionId.chooseArtwork,
        current,
        () async {
          called = true;
        },
      ),
      throwsStateError,
    );
    expect(called, false);
  });
  test('coordinator deduplicates requests but releases them after completion and failure', () async {
    final owner = Object(), gate = Completer<void>();
    final coordinator = NavigationCoordinator.forOwner(owner);
    var calls = 0;
    final first = coordinator.run('details', () async {
      calls++;
      await gate.future;
    });
    await coordinator.run('details', () async {
      calls++;
    });
    await coordinator.run('explicit-play', () async {
      calls++;
    });
    expect(calls, 2);
    gate.complete();
    await first;
    await expectLater(
      coordinator.run('details', () async => throw StateError('failed')),
      throwsStateError,
    );
    await coordinator.run('details', () async {
      calls++;
    });
    expect(calls, 3);
  });
  test('legacy settings sanitize malformed overrides and keep scope keys unchanged', () async {
    final store = SharedStore();
    final key = MediaNavigationSettings.key('a', 'series:b');
    expect(key, 'media:settings:["a","series:b"]');
    await store.writeState(key, {
      'openAction': 'invalid',
      'rate': double.infinity.toString(),
    });
    final parsed = await MediaNavigationSettings.load(store, key);
    expect(parsed.openAction, 'automatic');
    expect(parsed.rate, 0);
    await store.writeState(key, {'openAction': 'play', 'rate': 1.1});
    expect((await MediaNavigationSettings.load(store, key)).rate, 1.1);
  });
  testWidgets(
    'video title tap honors title override and denies locked collection',
    (tester) async {
      final store = SharedStore();
      final library = createLibraryController(store);
      addTearDown(library.dispose);
      const collection = VideoCollection(
        id: 'c',
        name: 'Videos',
        subtype: VideoSubtype.videos,
      );
      library.collections = [collection];
      final asset = VideoAsset(
        id: 'v',
        collectionId: 'c',
        uri: 'content://v',
        filename: 'v.mp4',
        metadata: {},
        durationMs: 1000,
        width: 100,
        height: 100,
        addedAt: 0,
      );
      var plays = 0, details = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              child: const Text('Open'),
              onPressed: () => openVideoTitle(
                context,
                library,
                asset,
                legacyDetails: false,
                details: () async {
                  details++;
                },
                play: () async {
                  plays++;
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(plays, 1);
      await store.writeState(
        MediaNavigationSettings.key('c', asset.mediaId.key),
        const MediaNavigationSettings(openAction: 'details').toJson(),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(details, 1);
      library.collections = [
        const VideoCollection(
          id: 'c',
          name: 'Locked',
          subtype: VideoSubtype.videos,
          locked: true,
        ),
      ];
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(details, 1);
      expect(plays, 1);
    },
  );
}
