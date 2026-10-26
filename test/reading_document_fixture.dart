import 'dart:async';

import 'package:multiplexr/src/reading/reading_library.dart';
import 'package:multiplexr/src/reading/reading_document_transaction.dart';
import 'package:multiplexr/src/reading/reading_document_draft.dart';

/// Infrastructure fixture setup only. Production callers have no document API.
extension ReadingDocumentFixture on ReadingLibrary {
  Future<void> updateFixture(
    String owner,
    FutureOr<void> Function(ReadingDocumentDraft) change,
  ) => update(
    owner,
    (transaction) => change((transaction as ReadingDocumentTransaction).draft),
  );
}
