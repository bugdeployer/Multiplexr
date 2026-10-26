import '../../../core/application/clock.dart';
import '../../../library/library_models.dart' show LibraryRoot;
import 'backup_document.dart';

class BackupVerificationTarget {
  const BackupVerificationTarget(
    this.id,
    this.name, {
    required this.reading,
    required this.allowed,
  });
  final String id, name;
  final bool reading, allowed;
}

class BackupVerification {
  const BackupVerification(this.verified, this.skipped, this.failed);
  final int verified, skipped;
  final List<String> failed;
  String get message =>
      '$verified collections verified.${skipped > 0 ? ' Unlock $skipped collections to verify their folders.' : ''}${failed.isNotEmpty ? ' Check Folder health for: ${failed.join(', ')}.' : ''}';
}

class BackupBusy implements Exception {
  const BackupBusy();
  String get message =>
      'Pause active scans and metadata jobs, then retry restoring the library.';
}

abstract interface class BackupPort {
  Future<bool> authenticate();
  Future<bool> hasLockedCollections();
  Future<int> lastExport();
  Future<void> saveLastExport(int milliseconds);
  Future<bool> export();
  Future<String?> pick();
  Future<void> prepareRestore();
  Future<void> restore(Map<String, dynamic> document);
  Future<LibraryRoot?> pickRoot();
  Future<List<BackupVerificationTarget>> verificationTargets();
  Future<bool> verify(BackupVerificationTarget target);
}

enum BackupExportResult { saved, cancelled, authenticationCancelled }

class BackupWorkflow {
  BackupWorkflow(this.port, {required this.clock, required this.active});
  bool authenticationCancelled = false;
  final BackupPort port;
  final Clock clock;
  final bool Function() active;
  Future<bool> authorize({bool incomingLocked = false}) async {
    authenticationCancelled = false;
    if (!active()) return false;
    if (!incomingLocked && !await port.hasLockedCollections()) return active();
    final allowed = await port.authenticate();
    authenticationCancelled = !allowed;
    return allowed && active();
  }

  Future<BackupExportResult> export() async {
    if (!await authorize()) return BackupExportResult.authenticationCancelled;
    final saved = await port.export();
    if (!saved) return BackupExportResult.cancelled;
    try {
      await port.saveLastExport(clock.now().millisecondsSinceEpoch);
    } catch (_) {
      /* File export remains successful if its timestamp cannot save. */
    }
    return BackupExportResult.saved;
  }

  Future<Map<String, dynamic>?> pick() async {
    if (!await authorize()) return null;
    final text = await port.pick();
    if (text == null || !active()) return null;
    final document = parseBackup(text);
    if (backupContainsLocked(document) &&
        !await authorize(incomingLocked: true)) {
      return null;
    }
    return active() ? document : null;
  }

  Future<bool> restore(
    Map<String, dynamic> document,
    Future<bool> Function() confirm,
  ) async {
    if (!await authorize(incomingLocked: backupContainsLocked(document)) ||
        !active()) {
      return false;
    }
    await port.prepareRestore();
    if (!await confirm() || !active()) return false;
    await port.restore(document);
    return true;
  }

  Future<bool> relink(
    Map<String, dynamic> document,
    Map<String, dynamic> collection,
    int index, {
    required bool reading,
  }) async {
    authenticationCancelled = false;
    final root = await port.pickRoot();
    if (root == null || !active()) return false;
    relinkBackupRoot(
      document,
      collection,
      index,
      root.uri,
      root.name,
      reading: reading,
    );
    return true;
  }

  Future<BackupVerification> verify() async {
    authenticationCancelled = false;
    var verified = 0, skipped = 0;
    final failed = <String>[];
    for (final target in await port.verificationTargets()) {
      if (!active()) break;
      if (!target.allowed) {
        skipped++;
        continue;
      }
      try {
        if (await port.verify(target)) {
          verified++;
        } else {
          failed.add(target.name);
        }
      } catch (_) {
        failed.add(target.name);
      }
    }
    return BackupVerification(verified, skipped, List.unmodifiable(failed));
  }
}
