import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/features/catalog/application/extension_catalog.dart';

class CatalogSource implements ExtensionCatalogSource {
  bool allowed = true;
  Completer<void>? gate;
  List<ExtensionTitle> rows = [];
  @override
  bool authorized(String collection, ExtensionMedia kind) => allowed;
  @override
  Future<List<ExtensionTitle>> titles(
    String collection,
    ExtensionMedia kind,
  ) async {
    await gate?.future;
    return rows;
  }
}

ExtensionTitle title(String id, {String revision = 'one'}) => ExtensionTitle(
  id: id,
  collection: 'books',
  kind: ExtensionMedia.ebook,
  title: 'Title $id',
  revision: revision,
);
void main() {
  test(
    'bounded typed extension pages detect revision drift and malformed cursors',
    () async {
      final source = CatalogSource()
        ..rows = [title('b'), title('a'), title('c')];
      final queries = ExtensionCatalogQueries(source);
      final page = await queries.titles(
        'books',
        ExtensionMedia.ebook,
        limit: 2,
      );
      expect(page.items.map((row) => row.id), ['a', 'b']);
      final last = await queries.titles(
        'books',
        ExtensionMedia.ebook,
        cursor: page.nextCursor,
      );
      expect(last.items.single.id, 'c');
      expect(last.nextCursor, isNull);
      source.rows = [title('a', revision: 'two'), title('b'), title('c')];
      await expectLater(
        queries.titles('books', ExtensionMedia.ebook, cursor: page.nextCursor),
        throwsA(isA<ExtensionCatalogConflict>()),
      );
      await expectLater(
        queries.titles('books', ExtensionMedia.ebook, limit: 101),
        throwsArgumentError,
      );
      await expectLater(
        queries.titles('books', ExtensionMedia.ebook, cursor: 'native:key'),
        throwsArgumentError,
      );
    },
  );
  test('revocation during read drops all results; wrong owners and duplicate identities fail closed', () async {
    final source = CatalogSource()
      ..rows = [title('a')]
      ..gate = Completer<void>();
    final queries = ExtensionCatalogQueries(source);
    final loading = queries.titles('books', ExtensionMedia.ebook);
    source.allowed = false;
    source.gate!.complete();
    await expectLater(loading, throwsStateError);
    source.allowed = true;
    source.gate = null;
    await expectLater(
      queries.titles('other', ExtensionMedia.ebook),
      throwsStateError,
    );
    source.rows = [title('a'), title('a')];
    await expectLater(
      queries.titles('books', ExtensionMedia.ebook),
      throwsStateError,
    );
  });
}
