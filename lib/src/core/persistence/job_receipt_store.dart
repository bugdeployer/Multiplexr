import '../application/job_admission.dart';
import 'state_repository.dart';

class LocalJobReceipts implements JobReceiptStore {
  const LocalJobReceipts(this.store);
  final StateStore store;
  static const key = 'ui:jobs:v1';
  @override
  Future<List<JobReceipt>> read() async {
    final value = await store.readState(key);
    if (value == null) return [];
    if (value.length != 2 ||
        value['version'] is! int ||
        value['version'] != 1 ||
        value['receipts'] is! List ||
        (value['receipts'] as List).length > 10000) {
      throw const FormatException('Invalid job receipt ledger');
    }
    final keys = <String>{};
    return (value['receipts'] as List).map((row) {
      if (row is! Map || row.length != 3 || !keys.add(row['key'] as String)) {
        throw const FormatException('Invalid job receipt');
      }
      return JobReceipt(
        row['key'] as String,
        List<String>.from(row['collections'] as List),
        JobOutcome.values.byName(row['outcome'] as String),
      );
    }).toList();
  }

  @override
  Future<void> write(List<JobReceipt> receipts) => store.writeState(key, {
    'version': 1,
    'receipts': [
      for (final receipt in receipts)
        {
          'key': receipt.key,
          'collections': receipt.collections,
          'outcome': receipt.outcome.name,
        },
    ],
  });
}
