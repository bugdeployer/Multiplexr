import 'support/space_controls.dart';

import 'package:multiplexr/src/bootstrap/reading_assembly.dart';
import 'package:multiplexr/src/bootstrap/library_assembly.dart';

import 'reading_document_fixture.dart';

import 'package:multiplexr/src/library/library_models.dart' show CatalogView;
import 'package:multiplexr/src/library/collection_form.dart';
import 'package:multiplexr/src/settings/domain/media_settings.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/catalog/domain/classification.dart';
import 'package:multiplexr/src/features/catalog/application/space_queries.dart';
import 'package:multiplexr/src/reading/domain/reading_codec.dart';
import 'package:multiplexr/src/reading/domain/reading_management.dart';
import 'package:multiplexr/src/reading/reading_app_controller.dart';
import 'package:multiplexr/src/reading/reading_collection_page.dart';
import 'package:multiplexr/src/reading/reading_space.dart';
import 'package:multiplexr/src/reading/reading_workflow_widgets.dart';
import 'package:multiplexr/src/space_preferences.dart';

import 'reading_r5_test.dart' show ReadingWorkflowHarness, detached;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixture = jsonDecode(
    File('test/fixtures/reading-spaces-v1.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  for (final raw in fixture['cases'] as List) {
    final c = raw as Map;
    test('space management wire: ${c['name']}', () {
      final value = detached(fixture['management'] as Map<String, dynamic>);
      dynamic target = value;
      final path = c['path'] as List;
      for (final key in path.take(path.length - 1)) {
        target = target[key];
      }
      target[path.last] = c['value'];
      final catalog = ReadingCodec.decode(
        fixture['catalog'] as Map<String, dynamic>,
      );
      if (c['valid'] == true) {
        expect(ReadingManagement(value, catalog).json, value);
      } else {
        expect(() => ReadingManagement(value, catalog), throwsFormatException);
      }
    });
  }
  ReadingAppController app(
    ReadingWorkflowHarness h, {
    bool Function()? blocked,
    Future<bool> Function()? auth,
  }) => createReadingAppController(
    h.service,
    authenticate: auth ?? () => Future.value(true),
    appBlocked: blocked ?? () => false,
  );
  test('global exclusions never remove local content; locks exclude global even after authentication', () async {
    final h = ReadingWorkflowHarness();
    final controller = app(h);
    addTearDown(controller.dispose);
    await controller.load();
    expect(
      controller.eligible(const SpaceScope(MediaSubtype.ebook)),
      hasLength(2),
    );
    await h.library.updateFixture(
      'books:[]',
      (d) =>
          (d.catalog['collections'] as List).first['includeInGlobal'] = false,
    );
    await controller.load();
    expect(controller.eligible(const SpaceScope(MediaSubtype.ebook)), isEmpty);
    expect(
      controller.eligible(
        const SpaceScope(MediaSubtype.ebook, collectionId: 'books:[]'),
      ),
      hasLength(2),
    );
    await h.library.updateFixture(
      'books:[]',
      (d) => (d.catalog['collections'] as List).first['locked'] = true,
    );
    await controller.load();
    expect(controller.canAccess('books:[]'), false);
    expect(await controller.unlock('books:[]'), true);
    expect(controller.eligible(const SpaceScope(MediaSubtype.ebook)), isEmpty);
    expect(
      controller.eligible(
        const SpaceScope(MediaSubtype.ebook, collectionId: 'books:[]'),
      ),
      hasLength(2),
    );
    controller.endSession('books:[]');
    expect(controller.canAccess('books:[]'), false);
  });
  test(
    'denied authentication and app lock never grant content access',
    () async {
      final h = ReadingWorkflowHarness();
      var blocked = false;
      (h.transport.state[ReadingCodec.key]!['collections'] as List)
              .first['locked'] =
          true;
      final a = app(h, blocked: () => blocked, auth: () => Future.value(false));
      addTearDown(a.dispose);
      await a.load();
      expect(await a.unlock('books:[]'), false);
      expect(
        a.eligible(
          const SpaceScope(MediaSubtype.ebook, collectionId: 'books:[]'),
        ),
        isEmpty,
      );
      blocked = true;
      a.securityChanged();
      expect(a.eligible(const SpaceScope(MediaSubtype.comics)), isEmpty);
    },
  );
  test(
    'removed collection revokes grants and empty refresh fails closed',
    () async {
      final h = ReadingWorkflowHarness(), a = app(ReadingWorkflowHarness());
      a.dispose();
      final c = app(h);
      addTearDown(c.dispose);
      await c.load();
      h.transport.state[ReadingCodec.key] = ReadingCodec.encode(
        c.bundle!.catalog.withoutCollection('books:[]'),
      );
      h.transport.state['reading:index:v1'] = {
        'version': 1,
        'entries': [],
        'roots': [],
        'orders': [],
        'replacements': [],
      };
      h.transport.state[ReadingManagement.key] = ReadingManagement.empty();
      await c.load();
      expect(c.canAccess('books:[]'), false);
      expect(c.eligible(const SpaceScope(MediaSubtype.ebook)), isEmpty);
    },
  );
  test('next unread derives source order and ignores finished and unavailable titles', () async {
    final h = ReadingWorkflowHarness();
    final a = app(h);
    addTearDown(a.dispose);
    await a.load();
    await a.library.group('books:[]', 'saga', 'Saga', ['standalone']);
    await a.load();
    expect(
      a
          .nextUnread(const SpaceScope(MediaSubtype.ebook))
          .single
          .catalog
          .id
          .entityId,
      'volume',
    );
    await a.library.finished('books:[]', [h.volume], true);
    await a.load();
    expect(
      a
          .nextUnread(const SpaceScope(MediaSubtype.ebook))
          .single
          .catalog
          .id
          .entityId,
      'standalone',
    );
    await a.library.updateFixture(
      'books:[]',
      (d) => (d.catalog['titles'] as List).first['source']['available'] = false,
    );
    await a.load();
    expect(a.nextUnread(const SpaceScope(MediaSubtype.ebook)), isEmpty);
  });
  test('reading lists are references and failed save does not change membership or progress', () async {
    final h = ReadingWorkflowHarness();
    final a = app(h);
    addTearDown(a.dispose);
    await a.load();
    final before = ReadingCodec.encode(a.bundle!.catalog);
    await a.saveList('books:[]', 'weekend', 'Weekend', [
      'volume',
      'standalone',
      'volume',
    ]);
    await a.load();
    expect(a.lists(const SpaceScope(MediaSubtype.ebook)).single.titles, [
      'volume',
      'standalone',
    ]);
    expect(ReadingCodec.encode(a.bundle!.catalog), before);
    h.transport.fail = true;
    await expectLater(
      a.saveList('books:[]', 'weekend', 'Lost', []),
      throwsStateError,
    );
    expect(
      (h.transport.state[ReadingManagement.key]!['lists'] as List)
          .single['name'],
      'Weekend',
    );
    h.transport.fail = false;
    await a.deleteList('books:[]', 'weekend');
    await a.load();
    expect(a.lists(const SpaceScope(MediaSubtype.ebook)), isEmpty);
  });
  test('global reading display persists without overwriting other space preferences', () async {
    final h = ReadingWorkflowHarness();
    final first = SpacePreferences(), second = SpacePreferences();
    await first.load(h.service.userPreferences);
    await second.load(h.service.userPreferences);
    first.ebook.pins = ['["books:[]","standalone"]'];
    first.ebook.startTab = 2;
    await first.save(h.service.userPreferences);
    second.music.artwork = false;
    await second.save(h.service.userPreferences);
    final restored = SpacePreferences();
    await restored.load(h.service.userPreferences);
    expect(restored.ebook.startTab, 2);
    expect(restored.ebook.pins, hasLength(1));
    expect(restored.music.artwork, false);
  });
  test(
    'nested local sessions retain a locked grant until the last route leaves',
    () async {
      final h = ReadingWorkflowHarness();
      (h.transport.state[ReadingCodec.key]!['collections'] as List)
              .first['locked'] =
          true;
      final a = app(h);
      addTearDown(a.dispose);
      await a.load();
      expect(await a.unlock('books:[]'), true);
      expect(await a.unlock('books:[]'), true);
      a.endSession('books:[]');
      expect(a.canAccess('books:[]'), true);
      a.endSession('books:[]');
      expect(a.canAccess('books:[]'), false);
    },
  );
  test('next series preview follows membership order while skipping finished members', () async {
    final h = ReadingWorkflowHarness();
    final a = app(h);
    addTearDown(a.dispose);
    await a.load();
    await a.library.group('books:[]', 'saga', 'Saga', ['standalone']);
    await a.load();
    final volume = a.bundle!.catalog.titles.singleWhere(
      (t) => t.catalog.id == h.volume,
    );
    expect(a.nextInSeries(volume)!.catalog.id, h.book);
    await a.library.finished('books:[]', [h.book], true);
    await a.load();
    expect(a.nextInSeries(volume), isNull);
  });
  test(
    'production registry binds both readers without external-engine claims',
    () {
      for (final subtype in [MediaSubtype.ebook, MediaSubtype.comics]) {
        final d = appSubtypes.requireEnabled(subtype);
        expect(
          d.capabilities,
          containsAll([
            MediaCapability.localSpace,
            MediaCapability.globalSpace,
          ]),
        );
        expect(d.capabilities, isNot(contains(MediaCapability.externalEngine)));
      }
      appSubtypes.validateBindings(
        collectionRoutes: appSubtypes.enabled.map((d) => d.id).toSet(),
        engines: {
          MediaEngineKind.video,
          MediaEngineKind.audio,
          MediaEngineKind.reader,
        },
      );
    },
  );
  test('unread at the initial position agrees with collection status after completion Undo', () async {
    final h = ReadingWorkflowHarness();
    final a = app(h);
    addTearDown(a.dispose);
    await a.load();
    final title = a.bundle!.catalog.titles.singleWhere(
      (t) => t.catalog.id == h.book,
    );
    await a.library.finished('books:[]', [h.book], true);
    await a.library.finished('books:[]', [h.book], false);
    await a.load();
    expect(a.progress(title), isNotNull);
    expect(a.finished(title), false);
    expect(a.started(title), false);
  });
  Future<void> show(
    WidgetTester tester,
    Widget child, {
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: child,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'space search filters results and returning from details preserves query',
    (tester) async {
      final h = ReadingWorkflowHarness();
      final a = app(h);
      await a.load();
      await show(
        tester,
        ReadingSpace(app: a, scope: const SpaceScope(MediaSubtype.ebook)),
      );
      await openSpaceControls(tester);
      await tester.tap(find.text('Browse'));
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.enterText(find.byType(TextField).first, 'standalone');
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'volume'), findsNothing);
      await openSpaceControls(tester);
      await tester.scrollUntilVisible(
        find.widgetWithText(ListTile, 'standalone').first,
        150,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.widgetWithText(ListTile, 'standalone').first);
      await tester.pumpAndSettle();
      expect(find.byType(ReadingTitleDetailsPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('standalone'), findsWidgets);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'standalone',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      a.dispose();
    },
  );
  testWidgets(
    'local display settings persist three pins and stay independent of global',
    (tester) async {
      final h = ReadingWorkflowHarness();
      final a = app(h);
      await a.load();
      await show(
        tester,
        ReadingSpace(
          app: a,
          scope: const SpaceScope(MediaSubtype.ebook, collectionId: 'books:[]'),
        ),
      );
      await openSpaceControls(tester);
      await tester.tap(find.byTooltip('Space settings'));
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.ensureVisible(
        find.widgetWithText(CheckboxListTile, 'standalone'),
      );
      await openSpaceControls(tester);
      await tester.tap(find.widgetWithText(CheckboxListTile, 'standalone'));
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
      await openSpaceControls(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      final row =
          (h.transport.state[ReadingManagement.key]!['spaces'] as List).single;
      expect(row['display']['pins'], ['["books:[]","standalone"]']);
      expect(h.transport.state['spaces:display'], isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      a.dispose();
    },
  );
  testWidgets('large text empty spaces stay usable in a narrow viewport', (
    tester,
  ) async {
    final h = ReadingWorkflowHarness();
    final a = app(h);
    await a.load();
    await a.library.updateFixture(
      'books:[]',
      (d) =>
          (d.catalog['collections'] as List).first['includeInGlobal'] = false,
    );
    await a.load();
    await tester.binding.setSurfaceSize(const Size(360, 640));
    await show(
      tester,
      ReadingSpace(app: a, scope: const SpaceScope(MediaSubtype.ebook)),
      scale: 1.8,
    );
    expect(find.byType(ReadingCover), findsNothing);
    expect(tester.takeException(), isNull);
    await openSpaceControls(tester);
    await tester.tap(find.text('Browse'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    a.dispose();
    await tester.binding.setSurfaceSize(null);
  });
  testWidgets('live revocation hides artwork and dismisses nested details', (
    tester,
  ) async {
    final h = ReadingWorkflowHarness();
    var blocked = false;
    final a = app(h, blocked: () => blocked);
    await a.load();
    await show(
      tester,
      ReadingAccessGuard(
        controller: a,
        collectionId: 'books:[]',
        child: ReadingSpace(
          app: a,
          scope: const SpaceScope(MediaSubtype.ebook, collectionId: 'books:[]'),
        ),
      ),
    );
    await openSpaceControls(tester);
    await tester.tap(find.text('Browse'));
    await tester.pumpAndSettle();
    await openSpaceControls(tester);
    await tester.scrollUntilVisible(
      find.widgetWithText(ListTile, 'standalone').first,
      150,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.widgetWithText(ListTile, 'standalone').first);
    await tester.pumpAndSettle();
    expect(find.byType(ReadingTitleDetailsPage), findsOneWidget);
    blocked = true;
    a.securityChanged();
    await tester.pumpAndSettle();
    expect(find.byType(ReadingCover), findsNothing);
    expect(find.byType(ReadingTitleDetailsPage), findsNothing);
    expect(find.text('Collection unavailable · Back'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    a.dispose();
  });
  testWidgets(
    'shared creation keeps name, roots and subtype draft after a failed reading save',
    (tester) async {
      final h = ReadingWorkflowHarness();
      final a = app(h);
      await a.load();
      final legacy = createLibraryController(h.service);
      await legacy.load();
      await show(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => collectionDialog(
                context,
                legacy,
                saveReading: (row, prefs) => a.create(row, preferences: prefs),
              ),
              child: const Text('Create'),
            ),
          ),
        ),
      );
      await openSpaceControls(tester);
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.enterText(find.byType(TextFormField).first, 'My books');
      await openSpaceControls(tester);
      await tester.tap(find.byType(DropdownButtonFormField<MediaType>));
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.tap(find.text('Audio').last);
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.ensureVisible(find.text('Add root folder'));
      await openSpaceControls(tester);
      await tester.tap(find.text('Add root folder'));
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.ensureVisible(
        find.byType(DropdownButtonFormField<MediaType>),
      );
      await openSpaceControls(tester);
      await tester.tap(find.byType(DropdownButtonFormField<MediaType>));
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.tap(find.text('Ebook').last);
      await tester.pumpAndSettle();
      expect(find.byType(CollectionForm), findsOneWidget);
      expect(find.byType(SimpleDialog), findsNothing);
      expect(
        find.text(
          'Use Series name / Audiobook title / audio files. A standalone title also has its own series.',
        ),
        findsNothing,
      );
      expect(find.text('My books'), findsOneWidget);
      await openSpaceControls(tester);
      await tester.ensureVisible(
        find.byType(DropdownButtonFormField<MediaSubtype>),
      );
      await openSpaceControls(tester);
      await tester.tap(find.byType(DropdownButtonFormField<MediaSubtype>));
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.tap(find.text('Comics').last);
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.ensureVisible(find.text('Create collection'));
      h.transport.fail = true;
      await openSpaceControls(tester);
      await tester.tap(find.text('Create collection'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not save the collection. Try again.'),
        findsOneWidget,
      );
      expect(
        a.bundle!.catalog.collections.any((c) => c.name == 'My books'),
        false,
      );
      h.transport.fail = false;
      await openSpaceControls(tester);
      await tester.tap(find.text('Create collection'));
      await tester.pumpAndSettle();
      final c = a.bundle!.catalog.collections.singleWhere(
        (c) => c.name == 'My books',
      );
      expect(c.subtype, MediaSubtype.comics);
      expect(c.roots.single.name, 'Chosen root');
      expect(legacy.collections, isEmpty);
      expect(
        a.bundle!.management.collections
            .singleWhere((r) => r.collectionId == c.id)
            .formats,
        ['cbz', 'images'],
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      a.dispose();
      legacy.dispose();
    },
  );
  testWidgets(
    'same subtype dropdown creates an empty Ebook collection without a route handoff',
    (tester) async {
      final h = ReadingWorkflowHarness();
      final a = app(h);
      await a.load();
      final legacy = createLibraryController(h.service);
      await legacy.load();
      await show(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => collectionDialog(
                context,
                legacy,
                saveReading: (row, prefs) => a.create(row, preferences: prefs),
              ),
              child: const Text('New'),
            ),
          ),
        ),
      );
      await openSpaceControls(tester);
      await tester.tap(find.text('New'));
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.enterText(find.byType(TextFormField).first, 'Empty books');
      await openSpaceControls(tester);
      await tester.tap(find.byType(DropdownButtonFormField<MediaType>));
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.tap(find.text('Ebook').last);
      await tester.pumpAndSettle();
      expect(find.byType(CollectionForm), findsOneWidget);
      expect(
        h.transport.calls.where((c) => c == 'commitReadingManagement'),
        isEmpty,
      );
      await openSpaceControls(tester);
      await tester.ensureVisible(find.text('Create collection'));
      await openSpaceControls(tester);
      await tester.tap(find.text('Create collection'));
      await tester.pumpAndSettle();
      expect(
        a.bundle!.catalog.collections
            .singleWhere((c) => c.name == 'Empty books')
            .roots,
        isEmpty,
      );
      expect(legacy.collections, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      a.dispose();
      legacy.dispose();
    },
  );
  testWidgets(
    'application typography persists at app scope and Reset removes the override',
    (tester) async {
      final h = ReadingWorkflowHarness();
      await show(
        tester,
        ReadingScopedSettingsPage(
          library: h.library,
          collectionId: 'books:[]',
          subtype: MediaSubtype.ebook,
          application: true,
        ),
      );
      await openSpaceControls(tester);
      await tester.scrollUntilVisible(find.text('Font size'), 250);
      await Scrollable.ensureVisible(
        tester.element(find.widgetWithText(ListTile, 'Font size')),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.tap(find.widgetWithText(ListTile, 'Font size'));
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.enterText(
        find.byKey(const ValueKey('reading-field-value')),
        '22',
      );
      await openSpaceControls(tester);
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
      await openSpaceControls(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      final catalog = (await h.library.read()).catalog;
      expect(
        catalog.settings
            .singleWhere((l) => l.scope == SettingsScope.app)
            .values['fontSize'],
        22.0,
      );
      await openSpaceControls(tester);
      await tester.scrollUntilVisible(find.text('Reset to inherited'), 300);
      await openSpaceControls(tester);
      await tester.tap(find.text('Reset to inherited'));
      await tester.pumpAndSettle();
      expect(
        (await h.library.read()).catalog.settings.where(
          (l) => l.scope == SettingsScope.app,
        ),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'showcase selection stops at three and preserves explicit pin order',
    (tester) async {
      final h = ReadingWorkflowHarness();
      final rows = h.transport.state[ReadingCodec.key]!['titles'] as List;
      for (final id in ['third', 'fourth']) {
        final row = detached(Map<String, dynamic>.from(rows.first as Map));
        row['id'] = id;
        row['metadata']['title'] = id;
        row['source']['id'] = '$id-source';
        row['source']['uri'] = 'content://local/$id';
        rows.add(row);
      }
      final a = app(h);
      await a.load();
      await show(
        tester,
        ReadingSpace(app: a, scope: const SpaceScope(MediaSubtype.ebook)),
      );
      await openSpaceControls(tester);
      await tester.tap(find.byTooltip('Space settings'));
      await tester.pumpAndSettle();
      for (final id in ['standalone', 'volume', 'third']) {
        final checkbox = find.widgetWithText(CheckboxListTile, id);
        await openSpaceControls(tester);
        await tester.ensureVisible(checkbox);
        await openSpaceControls(tester);
        await tester.tap(checkbox);
        await tester.pumpAndSettle();
      }
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'fourth'),
            )
            .onChanged,
        isNull,
      );
      tester
          .widget<ReorderableListView>(find.byType(ReorderableListView))
          .onReorderItem!(0, 2);
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
      await openSpaceControls(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      final restored = SpacePreferences();
      await restored.load(h.service.userPreferences);
      expect(restored.ebook.pins, [
        '["books:[]","volume"]',
        '["books:[]","third"]',
        '["books:[]","standalone"]',
      ]);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      a.dispose();
    },
  );
  testWidgets(
    'initial indexing stays in the collection instead of a creation wizard',
    (tester) async {
      final h = ReadingWorkflowHarness();
      await show(
        tester,
        ReadingCollectionPage(
          library: h.library,
          collectionId: 'books:[]',
          scanOnOpen: true,
        ),
      );
      expect(
        h.transport.calls,
        containsAll(['discoverReading', 'commitReadingScan']),
      );
      expect(find.byType(ReadingCollectionPage), findsOneWidget);
      expect(find.text('Folder health'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets('creating an empty collection skips initial indexing', (
    tester,
  ) async {
    final h = ReadingWorkflowHarness();
    final a = app(h);
    await a.load();
    await a.create({
      'id': 'empty',
      'name': 'Empty',
      'subtype': 'ebook',
      'locked': false,
      'includeInGlobal': true,
      'roots': [],
    });
    await show(
      tester,
      ReadingCollectionPage(
        library: a.library,
        collectionId: 'empty',
        scanOnOpen: true,
      ),
    );
    expect(h.transport.calls, isNot(contains('discoverReading')));
    expect(find.text('Empty'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    a.dispose();
  });
  testWidgets(
    'shared appearance navigation and file choices reach the reading collection',
    (tester) async {
      final h = ReadingWorkflowHarness();
      final a = app(h);
      await a.load();
      final legacy = createLibraryController(h.service);
      await legacy.load();
      await show(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => collectionDialog(
                context,
                legacy,
                saveReading: (row, prefs) => a.create(row, preferences: prefs),
              ),
              child: const Text('New'),
            ),
          ),
        ),
      );
      await openSpaceControls(tester);
      await tester.tap(find.text('New'));
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.enterText(
        find.byType(TextFormField).first,
        'Configured books',
      );
      final type = find.byType(DropdownButtonFormField<MediaType>);
      await openSpaceControls(tester);
      await tester.tap(type);
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.tap(find.text('Ebook').last);
      await tester.pumpAndSettle();
      final layout = find.byType(DropdownButtonFormField<CatalogView>);
      await openSpaceControls(tester);
      await tester.ensureVisible(layout);
      await openSpaceControls(tester);
      await tester.tap(layout);
      await tester.pumpAndSettle();
      expect(find.text('Poster wall'), findsNothing);
      await openSpaceControls(tester);
      await tester.tap(find.text('List').last);
      await tester.pumpAndSettle();
      final slider = find.byType(Slider);
      await openSpaceControls(tester);
      await tester.ensureVisible(slider);
      tester.widget<Slider>(slider).onChanged!(240);
      await tester.pumpAndSettle();
      final opening = find.byType(DropdownButtonFormField<String>);
      await openSpaceControls(tester);
      await tester.ensureVisible(opening);
      await openSpaceControls(tester);
      await tester.tap(opening);
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.tap(find.text('Open immediately').last);
      await tester.pumpAndSettle();
      final epub = find.widgetWithText(FilterChip, '.epub');
      await openSpaceControls(tester);
      await tester.ensureVisible(epub);
      await openSpaceControls(tester);
      await tester.tap(epub);
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.ensureVisible(find.text('Create collection'));
      await openSpaceControls(tester);
      await tester.tap(find.text('Create collection'));
      await tester.pumpAndSettle();
      final id = a.bundle!.catalog.collections
          .singleWhere((c) => c.name == 'Configured books')
          .id;
      final pref = a.bundle!.management.collections.singleWhere(
        (r) => r.collectionId == id,
      );
      expect(pref.layout, 'list');
      expect(pref.cardSize, 240.0);
      expect(pref.openAction, 'open');
      expect(pref.formats, ['pdf', 'txt']);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      a.dispose();
      legacy.dispose();
    },
  );
}
