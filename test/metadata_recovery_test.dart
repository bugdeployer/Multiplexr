import 'fixtures/legacy_metadata_assembly.dart';

import 'package:multiplexr/src/features/metadata/application/metadata_contracts.dart';

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/library/library_models.dart';

import 'phase_one_test.dart' show BatchLibrary, batchSetup;

class JournalLibrary extends BatchLibrary {
  String? failCode;
  bool failCheckpoint = false;
  bool preserveTagsUsed = false;
  @override
  Future<void> writeState(String key, Map<String, dynamic>? value) async {
    if (failCheckpoint) throw PlatformException(code: 'storage');
    if (value == null) {
      states.remove(key);
    } else {
      states[key] = Map<String, dynamic>.from(jsonDecode(jsonEncode(value)));
    }
  }

  @override
  Future<List<Map<String, dynamic>>> search(String type, String query) async {
    if (failCode != null) throw PlatformException(code: failCode!);
    return super.search(type, query);
  }

  @override
  Future<void> saveAsset(VideoAsset asset, {bool preserveTags = false}) async {
    preserveTagsUsed = preserveTags;
    await super.saveAsset(asset, preserveTags: preserveTags);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'metadata checkpoint survives a new job instance and never starts itself',
    () async {
      final service = JournalLibrary();
      final library = await batchSetup(service, 23);
      final job = createMetadataJob(library, library.collections.single);
      job.addListener(() {
        if (job.done == 5 && job.running) job.cancel();
      });
      await job.run();
      expect(job.remaining.length, 18);
      final queries = service.queries.length;
      final recovered = createMetadataJob(library, library.collections.single);
      await recovered.recover();
      expect(recovered.resumable, true);
      expect(service.queries.length, queries);
      expect(recovered.done, 5);
      await recovered.run(resume: true);
      expect(recovered.remaining, isEmpty);
      expect(service.saved.length, 23);
      expect(service.saved.toSet().length, 23);
      expect(service.preserveTagsUsed, true);
    },
  );
  test(
    'credential and rate-limit failures pause without consuming pending items',
    () async {
      for (final code in ['authentication', 'rateLimit']) {
        final service = JournalLibrary()..failCode = code;
        final library = await batchSetup(service, 4);
        final job = createMetadataJob(library, library.collections.single);
        await expectLater(
          job.run(),
          throwsA(anyOf(isA<PlatformException>(), isA<MetadataFailure>())),
        );
        expect(job.running, false);
        expect(job.remaining.length, 4);
        expect(service.saved, isEmpty);
        final recovered = createMetadataJob(
          library,
          library.collections.single,
        );
        await recovered.recover();
        expect(
          recovered.lastError,
          contains(code == 'authentication' ? 'credential' : 'rate limit'),
        );
        service.failCode = null;
        await recovered.run(resume: true);
        expect(recovered.remaining, isEmpty);
      }
    },
  );
  test(
    'storage checkpoint failure stops before provider requests or asset writes',
    () async {
      final service = JournalLibrary()..failCheckpoint = true;
      final library = await batchSetup(service, 2);
      final job = createMetadataJob(library, library.collections.single);
      await expectLater(
        job.run(),
        throwsA(anyOf(isA<PlatformException>(), isA<MetadataFailure>())),
      );
      expect(job.running, false);
      expect(service.queries, isEmpty);
      expect(service.saved, isEmpty);
      expect(job.lastError, contains('storage'));
    },
  );
  test('network failures retain actionable reasons and support explicit failed retry', () async {
    final service = JournalLibrary()..failCode = 'network';
    final library = await batchSetup(service, 3);
    final job = createMetadataJob(library, library.collections.single);
    await job.run();
    expect(job.failed, 3);
    expect(job.failures.length, 3);
    expect(job.lastError, contains('connection'));
    service.failCode = null;
    await job.run(failedOnly: true);
    expect(job.matched, 3);
    expect(job.failed, 0);
  });
  test(
    'resume preserves unavailable work until files are reconnected',
    () async {
      final service = JournalLibrary()..failCode = 'authentication';
      final library = await batchSetup(service, 2);
      final job = createMetadataJob(library, library.collections.single);
      await expectLater(
        job.run(),
        throwsA(anyOf(isA<PlatformException>(), isA<MetadataFailure>())),
      );
      service.assets[0]['available'] = false;
      await library.load();
      service.failCode = null;
      await job.run(resume: true);
      expect(job.remaining.length, 1);
      service.assets.firstWhere(
        (a) => a['id'] == job.remaining.single,
      )['available'] = true;
      await library.load();
      await job.run(resume: true);
      expect(job.remaining, isEmpty);
    },
  );
}
