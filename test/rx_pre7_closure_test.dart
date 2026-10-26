import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/bootstrap/reading_assembly.dart';
import 'fixtures/legacy_library_service.dart';
import 'package:multiplexr/src/reading/domain/reading_management.dart';
import 'package:multiplexr/src/features/settings/application/host_settings.dart';
import 'package:multiplexr/src/features/metadata/application/metadata_batch_journal.dart';

import 'reading_r5_test.dart'
    show ReadingWorkflowHarness, ReadingWorkflowTransport;

class HeldSnapshot extends ReadingWorkflowTransport {
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<T?> invokeMethod<T>(String method, [Object? arguments]) async {
    if (method == 'readingSnapshot') {
      entered.complete();
      await release.future;
    }
    return super.invokeMethod<T>(method, arguments);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'catalog read projections cannot mutate durable or nested state',
    () async {
      final h = ReadingWorkflowHarness();
      final before = jsonEncode(h.transport.state[ReadingManagement.key]);
      final bundle = await h.library.read();
      expect(() => bundle.index.entries.clear(), throwsUnsupportedError);
      expect(() => bundle.management.entities.clear(), throwsUnsupportedError);
      expect(
        () => bundle.management
            .entity(bundle.catalog.titles.first.catalog.id)
            .tags
            .add('injected'),
        throwsUnsupportedError,
      );
      expect(
        () => bundle.management.collections.clear(),
        throwsUnsupportedError,
      );
      expect(() => bundle.management.pageNotes.clear(), throwsUnsupportedError);
      expect(jsonEncode(h.transport.state[ReadingManagement.key]), before);
    },
  );
  test(
    'journal read projections detach and freeze provider candidate values',
    () {
      final values = <String, dynamic>{
        'authors': <String>['Original'],
      };
      final journal = MetadataBatchJournal(
        entries: {
          'title': {
            'candidates': [
              {'values': values},
            ],
          },
        },
      );
      (values['authors'] as List).add('Changed');
      final candidate =
          (journal.entries['title']!['candidates'] as List).single;
      expect(candidate['values']['authors'], ['Original']);
      expect(
        () => (candidate['values']['authors'] as List).add('Injected'),
        throwsUnsupportedError,
      );
      expect(
        () => journal.entries['title']!['status'] = 'applied',
        throwsUnsupportedError,
      );
    },
  );
  test(
    'preview authority rejects another adapter and consumed previews',
    () async {
      final h = ReadingWorkflowHarness(), other = ReadingWorkflowHarness();
      final scan = h.library.createScan();
      final preview = await scan.preview('books:[]');
      await expectLater(
        other.library.sources.commit(preview, checkAccess: () {}),
        throwsStateError,
      );
      expect(() => preview.sources.clear(), throwsUnsupportedError);
      await scan.apply('books:[]', preview);
      await expectLater(scan.apply('books:[]', preview), throwsStateError);
    },
  );
  test(
    'maintenance expires old previews but fresh scans remain usable',
    () async {
      final h = ReadingWorkflowHarness();
      final old = await h.library.createScan().preview('books:[]');
      await h.service.maintenance.exclusively(() async {});
      await expectLater(
        h.library.sources.commit(old, checkAccess: () {}),
        throwsStateError,
      );
      final fresh = h.library.createScan();
      final preview = await fresh.preview('books:[]');
      await fresh.apply('books:[]', preview);
    },
  );
  test('revocation during snapshot prevents native discovery', () async {
    final transport = HeldSnapshot();
    bool allowed = true;
    final library = createReadingLibrary(
      LibraryService(transport: transport),
      authorized: (_) => allowed,
    );
    final future = library.createScan().preview('books:[]');
    final rejection = expectLater(future, throwsStateError);
    await transport.entered.future;
    allowed = false;
    transport.release.complete();
    await rejection;
    expect(transport.calls, isNot(contains('discoverReading')));
  });
  test(
    'host defaults match native preferences and theme limits count bytes',
    () {
      expect(
        HostSettings.registry.definition('host.app.followSystem').defaultValue,
        false,
      );
      expect(
        HostSettings.registry.definition('host.app.pixel').defaultValue,
        true,
      );
      expect(
        HostSettings.registry.definition('host.app.notifications').defaultValue,
        false,
      );
      expect(
        HostSettings.registry.definition('host.app.lightAccent').defaultValue,
        7,
      );
      expect(
        () => HostSettings.validate('app', {'themeState': '界' * 6000000}),
        throwsArgumentError,
      );
    },
  );
}
