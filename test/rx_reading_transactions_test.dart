import 'dart:convert';

import 'package:multiplexr/src/reading/domain/reading_management.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/features/catalog/application/reading_catalog_ports.dart';

import 'reading_r5_test.dart' show ReadingWorkflowHarness;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'a retained reading transaction cannot mutate after its callback returns',
    () async {
      final harness = ReadingWorkflowHarness();
      final title = (await harness.library.read()).catalog.titles.first;
      late ReadingTransaction saved;
      await harness.library.update(title.catalog.id.collectionId, (
        transaction,
      ) {
        saved = transaction;
      });
      final before = jsonEncode(harness.transport.state[ReadingManagement.key]);
      await expectLater(
        saved.recordOpened(title.catalog.id, 1234),
        throwsStateError,
      );
      expect(
        jsonEncode(harness.transport.state[ReadingManagement.key]),
        before,
      );
    },
  );
  test(
    'cross-owner commands abort the whole transaction before persistence',
    () async {
      final harness = ReadingWorkflowHarness();
      final bundle = await harness.library.read();
      final title = bundle.catalog.titles.first;
      final owner = title.catalog.id.collectionId;
      final before = jsonEncode(harness.transport.state[ReadingManagement.key]);
      await expectLater(
        harness.library.update(owner, (transaction) async {
          await transaction.recordOpened(title.catalog.id, 1234);
          await transaction.restorePageNote(
            owner,
            const ReadingPageNote(
              id: 'note',
              collectionId: 'different-owner',
              titleId: 'title',
              sourceId: 'source',
              sourceRevision: 'rev',
              pageId: 'page',
              pageIndex: 0,
              offset: 0,
              kind: 'note',
              note: '',
              label: '',
            ),
          );
        }),
        throwsStateError,
      );
      expect(
        jsonEncode(harness.transport.state[ReadingManagement.key]),
        before,
      );
      await expectLater(
        harness.library.browse(owner, {'collectionId': 'different-owner'}),
        throwsStateError,
      );
      expect(
        jsonEncode(harness.transport.state[ReadingManagement.key]),
        before,
      );
    },
  );
}
