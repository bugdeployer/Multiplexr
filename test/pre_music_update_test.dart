import 'package:multiplexr/src/bootstrap/library_assembly.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/main.dart';
import 'package:multiplexr/src/experience/collection/job_status_page.dart';
import 'package:multiplexr/src/experience/navigation/browse_memory.dart';
import 'package:multiplexr/src/experience/navigation/navigation_origin.dart';
import 'package:multiplexr/src/library/library_models.dart';
import 'package:multiplexr/src/library/native_player.dart';
import 'package:multiplexr/src/media/navigation_settings.dart';
import 'package:multiplexr/src/settings/domain/media_settings.dart';
import 'package:app_shell/app_shell.dart';

import 'media_foundation_test.dart' show SharedStore;
import 'widget_test.dart' show TestDevice;

class DelayedBrowseStore extends SharedStore {
  final read = Completer<Map<String, dynamic>?>();
  @override
  Future<Map<String, dynamic>?> readState(String key) => read.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(AppThemeDefinition.loadBundled);

  test(
    'browsing state survives a new owner, is scoped, and resets explicitly',
    () async {
      final store = SharedStore();
      final query = TextEditingController(), scroll = ScrollController();
      var filter = 'all', tab = 0;
      BrowseMemory make(String? collection) => BrowseMemory(
        preferences: store.userPreferences,
        query: query,
        scroll: scroll,
        alive: () => true,
        capture: () => NavigationOrigin(
          routeId: 'videos',
          collectionId: collection,
          query: query.text,
          filter: filter,
          tab: tab,
        ),
        defaults: () => NavigationOrigin(
          routeId: 'videos',
          collectionId: collection,
          filter: 'all',
        ),
        apply: (origin) {
          filter = origin.filter;
          tab = origin.tab;
        },
      );
      final first = make('a');
      await first.restore();
      query.text = 'remember me';
      filter = 'favorite';
      tab = 1;
      first.changed();
      await first.flush();
      first.dispose();
      query.text = '';
      filter = 'all';
      tab = 0;
      final second = make('a');
      await second.restore();
      expect(query.text, 'remember me');
      expect(filter, 'favorite');
      expect(tab, 1);
      await second.reset();
      expect(query.text, isEmpty);
      expect(filter, 'all');
      expect(tab, 0);
      second.dispose();
      final other = make('b');
      await other.restore();
      expect(query.text, isEmpty);
      other.dispose();
      query.dispose();
      scroll.dispose();
    },
  );

  test('slow browse restore cannot overwrite newer user input or a different scope', () async {
    final store = DelayedBrowseStore();
    final query = TextEditingController(), scroll = ScrollController();
    var applied = false;
    final memory = BrowseMemory(
      preferences: store.userPreferences,
      query: query,
      scroll: scroll,
      alive: () => true,
      capture: () => NavigationOrigin(
        routeId: 'videos',
        collectionId: 'a',
        query: query.text,
      ),
      defaults: () =>
          const NavigationOrigin(routeId: 'videos', collectionId: 'a'),
      apply: (_) {
        applied = true;
      },
    );
    final restore = memory.restore();
    query.text = 'new input';
    store.read.complete(
      const NavigationOrigin(
        routeId: 'videos',
        collectionId: 'other',
        query: 'stale',
      ).toJson(),
    );
    await restore;
    expect(query.text, 'new input');
    expect(applied, isFalse);
    await memory.flush();
    memory.dispose();
    query.dispose();
    scroll.dispose();
  });

  testWidgets(
    'metadata editor shows inherited effective values without duplicating the resolver',
    (tester) async {
      final store = SharedStore();
      store.collections.add(
        const VideoCollection(
          id: 'a',
          name: 'Collection',
          subtype: VideoSubtype.videos,
          audioRate: 1.25,
        ).toJson(),
      );
      store.states[MediaNavigationSettings.key('a', 'series:s')] = {
        'openAction': 'details',
        'rate': 1.5,
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showMediaNavigationSettings(
                  context,
                  store,
                  MediaNavigationSettings.key('a', 'title'),
                  'Title',
                  ancestorIds: ['series:s'],
                ),
                child: const Text('Edit'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Effective: Show details · Series'), findsOneWidget);
      expect(find.text('Effective: 1.5x · Series'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'job overview uses existing journals and omits locked collection details',
    () async {
      final store = SharedStore();
      for (final id in ['public', 'private']) {
        store.collections.add(
          VideoCollection(
            id: id,
            name: id,
            subtype: VideoSubtype.videos,
            locked: id == 'private',
          ).toJson(),
        );
        store.states['metadata:$id'] = {
          'remaining': ['one'],
          'review': 2,
          'failures': {'x': 'network'},
        };
      }
      final library = createLibraryController(store);
      await library.load();
      library.scanning.add('public');
      library.scanProgress['public'] = {'found': 8};
      final jobs = await readCollectionJobs(library);
      expect(jobs.length, 2);
      expect(jobs.every((j) => j.collection.id == 'public'), isTrue);
      expect(
        jobs.where((j) => j.metadata).single.summary,
        contains('0 to review'),
      );
      library.scanning.clear();
      store.states['metadata:public']!['remaining'] = [];
      expect(
        await readCollectionJobs(library),
        isEmpty,
        reason: 'Historical batch counts must not resurrect completed work',
      );
      library.dispose();
    },
  );

  test('parent provenance excludes the edited title while retaining series overrides', () async {
    final store = SharedStore();
    const collection = VideoCollection(
      id: 'a',
      name: 'Audio',
      subtype: VideoSubtype.videos,
      audioRate: 1.25,
    );
    store.states[MediaNavigationSettings.key('a', 'series:s')] = {
      'openAction': 'details',
      'rate': 1.5,
    };
    store.states[MediaNavigationSettings.key('a', 'title')] = {
      'openAction': 'play',
      'rate': 2.0,
    };
    final inherited = await resolveMediaNavigation(
      store,
      collection: collection,
      collectionId: 'a',
      titleId: 'title',
      ancestorIds: ['series:s'],
      includeTitle: false,
    );
    expect(inherited.rate.value, 1.5);
    expect(inherited.rate.scope, SettingsScope.group);
    expect(inherited.opening.value, TitleOpenAction.details);
    final own = await resolveMediaNavigation(
      store,
      collection: collection,
      collectionId: 'a',
      titleId: 'title',
      ancestorIds: ['series:s'],
    );
    expect(own.rate.value, 2.0);
    expect(own.rate.scope, SettingsScope.title);
  });

  testWidgets(
    'PiP stays visible under app lock and genuine PiP closure relocks browsing',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final device = TestDevice()..values['lockEnabled'] = true;
      final store = SharedStore();
      final window = PlaybackWindow.instance;
      window.active = false;
      window.backgrounded = false;
      Future<void> event(String method, bool value) =>
          tester.binding.defaultBinaryMessenger.handlePlatformMessage(
            'multiplexr/playback',
            const StandardMethodCodec().encodeMethodCall(
              MethodCall(method, value),
            ),
            (_) {},
          );
      await tester.pumpWidget(
        MultiplexrApp(platform: device, libraryService: store),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      await event('pipChanged', true);
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();
      expect(find.text('Multiplexr is locked'), findsNothing);
      expect(find.text('LIBRARY'), findsWidgets);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await event('pipChanged', false);
      await tester.pumpAndSettle();
      expect(find.text('Multiplexr is locked'), findsNothing);
      await event('pipChanged', true);
      await event('pipBackgrounded', true);
      await tester.pumpAndSettle();
      expect(find.text('Multiplexr is locked'), findsOneWidget);
      // A late PiP event is never an authentication bypass.
      await event('pipChanged', true);
      await tester.pumpAndSettle();
      expect(find.text('Multiplexr is locked'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      window.active = false;
      window.backgrounded = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    },
  );
}
