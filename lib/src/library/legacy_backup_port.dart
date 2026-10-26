import 'dart:convert';

import '../core/application/maintenance.dart';

import '../features/backup/application/backup_workflow.dart';
import '../reading/domain/reading_codec.dart';
import '../reading/reading_changes.dart';
import '../reading/reading_scan.dart';
import 'library_adapter_host.dart';
import 'library_models.dart';

class LegacyBackupPort implements BackupPort {
  const LegacyBackupPort(this.library, {required this.authentication});
  final LibraryAdapterHost library;
  final Future<bool> Function() authentication;
  @override
  Future<bool> authenticate() => authentication();
  @override
  Future<bool> hasLockedCollections() async {
    final reading = await library.service.readState(ReadingCodec.key);
    return library.collections.any((c) => c.locked) ||
        (reading?['collections'] as List? ?? []).any(
          (c) => c['locked'] == true,
        );
  }

  @override
  Future<int> lastExport() async =>
      (await library.service.readState('ui:backup'))?['lastExportAt'] ?? 0;
  @override
  Future<void> saveLastExport(int milliseconds) =>
      library.service.writeState('ui:backup', {'lastExportAt': milliseconds});
  @override
  Future<bool> export() => library.service.exportBackup();
  @override
  Future<String?> pick() => library.service.readBackup();
  @override
  Future<LibraryRoot?> pickRoot() => library.service.pickRoot();
  @override
  Future<void> prepareRestore() async {
    if (library.service.maintenance.exclusive ||
        library.service.maintenance.active ||
        library.scanning.isNotEmpty ||
        library.metadataRunning ||
        library.otherJobsRunning?.call() == true) {
      throw const BackupBusy();
    }
  }

  @override
  Future<void> restore(Map<String, dynamic> document) async {
    await prepareRestore();
    final maintenance = library.service.maintenance;
    final generation = maintenance.generation;
    try {
      await library.service.maintenance.exclusively(() async {
        await library.service.restoreBackup(jsonEncode(document));
        library.endCollectionSession();
        await library.load();
      });
    } on MaintenanceBusy {
      throw const BackupBusy();
    } catch (_) {
      if (maintenance.generation != generation) {
        try {
          await library.load();
        } catch (_) {
          /* Preserve the restore error. */
        }
      }
      rethrow;
    } finally {
      if (maintenance.generation != generation) {
        ReadingChanges.forOwner(library.service.persistenceOwner).changed();
      }
    }
  }

  @override
  Future<List<BackupVerificationTarget>> verificationTargets() async {
    final reading = await library.service.readState(ReadingCodec.key);
    final catalog = reading == null ? null : ReadingCodec.decode(reading);
    return [
      for (final c in library.collections)
        BackupVerificationTarget(
          c.id,
          c.name,
          reading: false,
          allowed: library.canAccessCollection(c.id),
        ),
      for (final c in catalog?.collections ?? [])
        BackupVerificationTarget(
          c.id,
          c.name,
          reading: true,
          allowed: !c.access.locked,
        ),
    ];
  }

  @override
  Future<bool> verify(BackupVerificationTarget target) async {
    if (!target.reading) {
      if (!library.canAccessCollection(target.id)) return false;
      await library.scan(target.id);
      return true;
    }
    final scanner = ReadingScanService(
      library.service,
      authorized: (id) => id == target.id && target.allowed,
    );
    final preview = await scanner.preview(target.id);
    if (!preview.canApply) return false;
    await scanner.apply(target.id, preview);
    return true;
  }
}
