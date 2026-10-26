import 'support/space_controls.dart';

import 'package:multiplexr/src/bootstrap/metadata_assembly.dart';
import 'package:multiplexr/src/bootstrap/settings_assembly.dart';
import 'package:multiplexr/src/bootstrap/reading_assembly.dart';
import 'package:multiplexr/src/bootstrap/library_assembly.dart';

import 'reading_document_fixture.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/reading/reading_management_pages.dart';

import 'reading_r5_test.dart' show ReadingWorkflowHarness;
import 'reading_ui_parity_test.dart' show ParityDevice;
import 'library_test.dart' show MemoryLibrary;

import 'package:multiplexr/src/library/collection_form.dart';
import 'package:multiplexr/src/library/library_models.dart';
import 'package:multiplexr/src/media/contracts.dart';
import 'package:app_shell/app_shell.dart';
import 'package:multiplexr/src/reading/reading_collection_page.dart';
import 'package:multiplexr/src/reading/reading_activity.dart';
import 'package:multiplexr/src/reading/reading_space.dart';
import 'package:multiplexr/src/reading/reading_metadata_page.dart';
import 'package:multiplexr/src/experience/collection/job_status_page.dart';
import 'package:multiplexr/src/features/catalog/application/space_queries.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppThemeDefinition.loadBundled();
  });
  for (final owner in ['books:[]', 'comics']) {
    testWidgets('$owner file-type edits persist after reopening', (
      tester,
    ) async {
      final h = ReadingWorkflowHarness();
      Future<void> open() async {
        await h.show(
          tester,
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ReadingCollectionSettingsPage(
                      library: h.library,
                      collectionId: owner,
                    ),
                  ),
                ),
                child: const Text('Settings'),
              ),
            ),
          ),
        );
        await openSpaceControls(tester);
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();
      }

      await open();
      final label = owner == 'comics' ? '.cbz' : '.epub';
      final chip = find.widgetWithText(FilterChip, label);
      await openSpaceControls(tester);
      await tester.scrollUntilVisible(
        chip,
        400,
        scrollable: find.byType(Scrollable).last,
      );
      expect(tester.widget<FilterChip>(chip).selected, true);
      await Scrollable.ensureVisible(tester.element(chip), alignment: .5);
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(chip).selected, false);
      await openSpaceControls(tester);
      await tester.ensureVisible(find.text('Save collection'));
      await openSpaceControls(tester);
      await tester.tap(find.text('Save collection'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not save the collection. Try again.'),
        findsNothing,
      );
      await open();
      await openSpaceControls(tester);
      await tester.scrollUntilVisible(
        chip,
        400,
        scrollable: find.byType(Scrollable).last,
      );
      expect(tester.widget<FilterChip>(chip).selected, false);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
  for (final retro in [false, true]) {
    for (final owner in ['books:[]', 'comics']) {
      testWidgets(
        '$owner shared extension editor persists formats and preserves preferences retro=$retro',
        (tester) async {
          final h = ReadingWorkflowHarness();
          await h.library.browse(owner, {
            'sort': 'source',
            'layout': 'compact',
            'openAction': 'open',
          });
          await h.library.updateFixture(
            owner,
            (d) => (d.management['collections'] as List).singleWhere(
              (r) => r['collectionId'] == owner,
            )['cardSize'] = 220,
          );
          final original = await h.library.read();
          final settings = createSettingsController(ParityDevice(0, retro));
          await settings.load();
          Future<void> open() async {
            await tester.pumpWidget(
              MaterialApp(
                theme: settings.theme,
                home: Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => ReadingCollectionSettingsPage(
                            library: h.library,
                            collectionId: owner,
                          ),
                        ),
                      ),
                      child: const Text('Open'),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            await openSpaceControls(tester);
            await tester.tap(find.text('Open'));
            await tester.pumpAndSettle();
          }

          await open();
          final label = owner == 'comics' ? '.cbz' : '.txt';
          final chip = find.widgetWithText(FilterChip, label);
          await openSpaceControls(tester);
          await tester.scrollUntilVisible(
            chip,
            400,
            scrollable: find.byType(Scrollable).last,
          );
          await Scrollable.ensureVisible(tester.element(chip), alignment: .5);
          await tester.pumpAndSettle();
          await openSpaceControls(tester);
          await tester.tap(chip);
          await tester.pumpAndSettle();
          expect(tester.widget<FilterChip>(chip).selected, false);
          final extension = find.widgetWithText(TextField, 'Other extension');
          await openSpaceControls(tester);
          await tester.ensureVisible(extension);
          await openSpaceControls(tester);
          await tester.enterText(extension, owner == 'comics' ? 'CBZ' : 'TXT');
          await openSpaceControls(tester);
          await tester.ensureVisible(find.byTooltip('Add extension'));
          await tester.pumpAndSettle();
          await openSpaceControls(tester);
          await tester.tap(find.byTooltip('Add extension'));
          await tester.pumpAndSettle();
          expect(tester.widget<FilterChip>(chip).selected, true);
          await openSpaceControls(tester);
          await tester.enterText(extension, 'mobi');
          await openSpaceControls(tester);
          await tester.ensureVisible(find.byTooltip('Add extension'));
          await tester.pumpAndSettle();
          await openSpaceControls(tester);
          await tester.tap(find.byTooltip('Add extension'));
          await tester.pumpAndSettle();
          expect(find.textContaining('The reader supports'), findsOneWidget);
          // Unsupported files never get silently advertised as readable.
          expect(find.widgetWithText(FilterChip, '.mobi'), findsNothing);
          await openSpaceControls(tester);
          await tester.enterText(extension, owner == 'comics' ? 'cbz' : 'txt');
          await openSpaceControls(tester);
          await tester.ensureVisible(find.byTooltip('Add extension'));
          await tester.pumpAndSettle();
          await openSpaceControls(tester);
          await tester.tap(find.byTooltip('Add extension'));
          await tester.pumpAndSettle();
          await Scrollable.ensureVisible(tester.element(chip), alignment: .5);
          await tester.pumpAndSettle();
          await openSpaceControls(tester);
          await tester.tap(chip);
          await tester.pumpAndSettle();
          await openSpaceControls(tester);
          await tester.ensureVisible(find.text('Save collection'));
          await openSpaceControls(tester);
          await tester.tap(find.text('Save collection'));
          await tester.pumpAndSettle();
          final saved = await h.library.read();
          final pref = saved.management.collections.singleWhere(
            (r) => r.collectionId == owner,
          );
          expect(
            pref.formats,
            owner == 'comics' ? ['images'] : ['epub', 'pdf'],
          );
          expect(pref.sort, 'source');
          expect(pref.layout, 'compact');
          expect(pref.cardSize, 220);
          expect(pref.openAction, 'open');
          expect(saved.catalog.titles.length, original.catalog.titles.length);
          expect(
            saved.catalog.progress.length,
            original.catalog.progress.length,
          );
          await open();
          await openSpaceControls(tester);
          await tester.scrollUntilVisible(
            chip,
            400,
            scrollable: find.byType(Scrollable).last,
          );
          expect(tester.widget<FilterChip>(chip).selected, false);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          settings.dispose();
        },
      );
    }
    for (final type in ['cinema', 'videos', 'audiobook', 'music']) {
      testWidgets('$type extension editor remains usable retro=$retro', (
        tester,
      ) async {
        final service = MemoryLibrary();
        final row = VideoCollection(
          id: type,
          name: type,
          subtype: type == 'cinema' ? VideoSubtype.cinema : VideoSubtype.videos,
          kind: type == 'audiobook'
              ? MediaKind.audiobook
              : type == 'music'
              ? MediaKind.music
              : MediaKind.video,
          extensions: type == 'audiobook' || type == 'music'
              ? ['mp3', 'm4b']
              : ['mp4'],
        );
        service.collections.add(row.toJson());
        final library = createLibraryController(service);
        await library.load();
        final settings = createSettingsController(ParityDevice(0, retro));
        await settings.load();
        await tester.pumpWidget(
          MaterialApp(
            theme: settings.theme,
            home: CollectionForm(
              library: library,
              existing: library.collections.single,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final extension = find.widgetWithText(TextField, 'Other extension');
        await openSpaceControls(tester);
        await tester.scrollUntilVisible(
          extension,
          400,
          scrollable: find.byType(Scrollable).last,
        );
        await openSpaceControls(tester);
        await tester.enterText(extension, 'custom');
        await openSpaceControls(tester);
        await tester.ensureVisible(find.byTooltip('Add extension'));
        await tester.pumpAndSettle();
        await openSpaceControls(tester);
        await tester.tap(find.byTooltip('Add extension'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FilterChip>(find.widgetWithText(FilterChip, '.custom'))
              .selected,
          true,
        );
        await openSpaceControls(tester);
        await tester.ensureVisible(find.text('Save collection'));
        await openSpaceControls(tester);
        await tester.tap(find.text('Save collection'));
        await tester.pumpAndSettle();
        expect(service.collections.single['extensions'], contains('custom'));
        expect(tester.takeException(), null);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        library.dispose();
        settings.dispose();
      });
    }
  }
  testWidgets(
    'collection settings apply layout immediately without clearing the search',
    (tester) async {
      final h = ReadingWorkflowHarness();
      await h.show(
        tester,
        ReadingCollectionPage(library: h.library, collectionId: 'books:[]'),
      );
      await openSpaceControls(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Search collection'),
        'standalone',
      );
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.tap(find.byTooltip('Collection settings'));
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.scrollUntilVisible(
        find.text('Default view'),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      final view = find.byType(DropdownButtonFormField<CatalogView>);
      await openSpaceControls(tester);
      await tester.tap(view);
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.tap(find.text('Grid').last);
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.scrollUntilVisible(
        find.text('Save collection'),
        400,
        scrollable: find.byType(Scrollable).last,
      );
      await openSpaceControls(tester);
      await tester.tap(find.text('Save collection'));
      await tester.pumpAndSettle();
      expect(find.byType(GridView), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, 'Search collection'),
            )
            .controller!
            .text,
        'standalone',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'reading space restores search and tabs after reopening and Reset keeps media',
    (tester) async {
      final h = ReadingWorkflowHarness();
      final app = createReadingAppController(
        h.service,
        authenticate: () async => true,
        appBlocked: () => false,
      );
      await app.load();
      Future<void> open() async {
        await h.show(
          tester,
          ReadingSpace(app: app, scope: const SpaceScope(MediaSubtype.ebook)),
        );
      }

      await open();
      await openSpaceControls(tester);
      await tester.tap(find.text('Browse'));
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.enterText(find.byType(TextField).first, 'standalone');
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await open();
      await openSpaceControls(tester);
      expect(
        tester
            .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
            .selected,
        {false},
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'standalone',
      );
      await openSpaceControls(tester);
      await tester.tap(find.byTooltip('Space actions'));
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.tap(find.text('Reset browsing'));
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
            .selected,
        {true},
      );
      expect((await h.library.read()).catalog.titles.length, 3);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      app.dispose();
    },
  );
  testWidgets(
    'shared Activity includes reading journals and hides them on live revocation',
    (tester) async {
      final h = ReadingWorkflowHarness();
      final app = createReadingAppController(
        h.service,
        authenticate: () async => true,
        appBlocked: () => false,
      );
      await app.load();
      final job = createReadingMetadataJob(app.library, 'books:[]', h.provider);
      await job.start(['standalone'], replace: true);
      await app.load();
      var opened = '';
      final legacy = createLibraryController(h.service);
      await legacy.load();
      await h.show(
        tester,
        JobStatusPage(
          library: legacy,
          openCollection: (_, _) async {},
          additionalChanges: app,
          additionalJobs: () => readReadingActivity(app, (id) async {
            opened = id;
          }),
        ),
      );
      expect(
        find.byKey(const ValueKey('activity:reading:books:[]')),
        findsOneWidget,
      );
      await openSpaceControls(tester);
      await tester.tap(find.byKey(const ValueKey('activity:reading:books:[]')));
      await tester.pumpAndSettle();
      expect(opened, 'books:[]');
      await app.library.updateFixture(
        'books:[]',
        (d) => (d.catalog['collections'] as List).first['locked'] = true,
      );
      await app.load();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('activity:reading:books:[]')),
        findsNothing,
      );
      expect(find.text('No pending jobs.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      job.dispose();
      legacy.dispose();
      app.dispose();
    },
  );
  for (final owner in ['books:[]', 'comics']) {
    testWidgets(
      '$owner empty file types cannot save and failed format saves retain the draft',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(360, 740);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final h = ReadingWorkflowHarness();
        await h.show(
          tester,
          ReadingCollectionSettingsPage(
            library: h.library,
            collectionId: owner,
          ),
          scale: 1.8,
        );
        for (final label
            in owner == 'comics'
                ? ['.cbz', 'Image chapters (JPEG/PNG/WebP)']
                : ['.epub', '.txt', '.pdf']) {
          final chip = find.widgetWithText(FilterChip, label);
          await openSpaceControls(tester);
          await tester.scrollUntilVisible(
            chip,
            300,
            scrollable: find.byType(Scrollable).last,
          );
          await Scrollable.ensureVisible(tester.element(chip), alignment: .5);
          await tester.pumpAndSettle();
          await openSpaceControls(tester);
          await tester.tap(chip);
          await tester.pumpAndSettle();
        }
        await openSpaceControls(tester);
        await tester.ensureVisible(find.text('Save collection'));
        await openSpaceControls(tester);
        await tester.tap(find.text('Save collection'));
        await tester.pumpAndSettle();
        expect(find.text('Select at least one file type.'), findsOneWidget);
        final extension = find.widgetWithText(TextField, 'Other extension');
        await openSpaceControls(tester);
        await tester.ensureVisible(extension);
        await openSpaceControls(tester);
        await tester.enterText(extension, owner == 'comics' ? 'png' : 'TXT');
        await openSpaceControls(tester);
        await tester.ensureVisible(find.byTooltip('Add extension'));
        await tester.pumpAndSettle();
        await openSpaceControls(tester);
        await tester.tap(find.byTooltip('Add extension'));
        await tester.pumpAndSettle();
        h.transport.fail = true;
        await openSpaceControls(tester);
        await tester.ensureVisible(find.text('Save collection'));
        await openSpaceControls(tester);
        await tester.tap(find.text('Save collection'));
        await tester.pumpAndSettle();
        expect(
          find.text('Could not save the collection. Try again.'),
          findsOneWidget,
        );
        final chip = find.widgetWithText(
          FilterChip,
          owner == 'comics' ? 'Image chapters (JPEG/PNG/WebP)' : '.txt',
        );
        expect(tester.widget<FilterChip>(chip).selected, true);
        h.transport.fail = false;
        await openSpaceControls(tester);
        await tester.tap(find.text('Save collection'));
        await tester.pumpAndSettle();
        expect(
          (await h.library.read()).management.collections,
          contains(
            predicate(
              (dynamic row) =>
                  row.collectionId == owner && row.formats.length == 1,
            ),
          ),
        );
        expect(tester.takeException(), null);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }
  testWidgets(
    'title actions handle I/O failures and guard duplicate reader opens',
    (tester) async {
      final h = ReadingWorkflowHarness();
      final gate = Completer<void>();
      var opened = 0;
      await h.show(
        tester,
        ReadingTitleDetailsPage(
          library: h.library,
          identity: h.book,
          actions: (_) async {
            throw StateError('Storage unavailable');
          },
          open: () async {
            opened++;
            await gate.future;
          },
        ),
      );
      await openSpaceControls(tester);
      await tester.tap(find.byTooltip('Title actions'));
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Could not open this action. Retry.'), findsOneWidget);
      ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first))
          .clearSnackBars();
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.scrollUntilVisible(
        find.text('Read'),
        400,
        scrollable: find.byType(Scrollable).last,
      );
      await openSpaceControls(tester);
      await tester.tap(find.text('Read'));
      await tester.pump();
      await openSpaceControls(tester);
      await tester.tap(find.text('Read'));
      await tester.pump();
      expect(opened, 1);
      gate.completeError(StateError('Source unavailable'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not open this title. Check its source and retry.'),
        findsOneWidget,
      );
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'Activity destination opens the reading metadata journal directly',
    (tester) async {
      final h = ReadingWorkflowHarness();
      await h.show(
        tester,
        ReadingCollectionPage(
          library: h.library,
          collectionId: 'books:[]',
          showJobs: true,
          provider: h.provider,
        ),
      );
      expect(find.text('Metadata lookup results'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      expect(
        find.widgetWithText(TextField, 'Search collection'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'reading-list deletion confirms, retains a failed draft, and preserves titles',
    (tester) async {
      final h = ReadingWorkflowHarness();
      final app = createReadingAppController(
        h.service,
        authenticate: () async => true,
        appBlocked: () => false,
      );
      await app.load();
      await app.saveList('books:[]', 'test-list', 'Reading queue', [
        'standalone',
      ]);
      await app.load();
      await h.show(
        tester,
        ReadingSpace(app: app, scope: const SpaceScope(MediaSubtype.ebook)),
      );
      await openSpaceControls(tester);
      await tester.tap(find.text('Browse'));
      await tester.pumpAndSettle();
      final row = find.widgetWithText(ListTile, 'Reading queue');
      await openSpaceControls(tester);
      await tester.scrollUntilVisible(
        row,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await openSpaceControls(tester);
      await tester.tap(
        find.descendant(
          of: row,
          matching: find.byType(PopupMenuButton<String>),
        ),
      );
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.tap(find.text('Delete list'));
      await tester.pumpAndSettle();
      expect(find.text('Delete reading list?'), findsOneWidget);
      expect(
        app
            .lists(const SpaceScope(MediaSubtype.ebook))
            .any((r) => r.id == 'test-list'),
        true,
      );
      h.transport.fail = true;
      await openSpaceControls(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not save. Your draft is retained.'),
        findsOneWidget,
      );
      h.transport.fail = false;
      await openSpaceControls(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      await app.load();
      expect(
        app
            .lists(const SpaceScope(MediaSubtype.ebook))
            .any((r) => r.id == 'test-list'),
        false,
      );
      expect((await h.library.read()).catalog.titles.length, 3);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      app.dispose();
    },
  );
  test(
    'controller collection deletion uses the same atomic removal command',
    () async {
      final h = ReadingWorkflowHarness();
      final app = createReadingAppController(
        h.service,
        authenticate: () async => true,
        appBlocked: () => false,
      );
      addTearDown(app.dispose);
      await app.load();
      await app.deleteCollection('books:[]');
      expect(app.error, null);
      expect(app.bundle!.catalog.collections.map((c) => c.id), ['comics']);
      expect(app.bundle!.catalog.titles.length, 1);
    },
  );
  testWidgets('series artwork source disables members without a cover', (
    tester,
  ) async {
    final h = ReadingWorkflowHarness();
    final group = (await h.library.read()).catalog.groups.first;
    await h.show(
      tester,
      ReadingArtworkPage(
        library: h.library,
        identity: group.id,
        provider: h.provider,
      ),
    );
    final tile = find.widgetWithText(ListTile, 'From volume');
    expect(tester.widget<ListTile>(tile).onTap, null);
    expect(find.text('No artwork'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
