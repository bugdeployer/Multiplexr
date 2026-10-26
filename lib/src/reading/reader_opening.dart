import 'ebook_opening_host.dart';
import '../features/reading/application/reader_handoff.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'comic_reader_page.dart';
import 'domain/reader_settings.dart';
import 'domain/reading_catalog.dart';
import 'domain/reading_location.dart';
import 'reader_choice.dart';
import '../features/settings/application/reader_preferences.dart';
import 'text_reader_page.dart';

/// Every ebook entry point resolves the same inherited, per-format preference.
Future<void> openEbookReader(
  BuildContext context,
  EbookOpeningHost service,
  ReadingTitle title, {
  required bool Function(String) authorized,
  TextReadingLocation? initialLocation,
  bool choose = false,
}) async {
  bool allowed() =>
      context.mounted && authorized(title.catalog.id.collectionId);
  bool allowedCollection(String id) => context.mounted && authorized(id);
  if (!context.mounted || !allowed()) return;
  final catalog = await service.readingPreferences();
  if (!context.mounted || !allowed()) return;
  var choice =
      resolveReaderPreferences(
            catalog,
            title,
          )[ReaderSettings.readerKey(title.format)]?.value
          as String? ??
      'internal';
  if (choose || choice == 'ask') {
    choice = await chooseReader(context, service, title.format.name) ?? '';
    if (choice.isEmpty || !allowed()) return;
  }
  while (choice.startsWith('app:')) {
    try {
      await ReaderHandoff(
        service.externalReader(),
        authorized: allowedCollection,
      ).open(title, choice.substring(4));
      return;
    } on PlatformException catch (error) {
      if (!context.mounted || !allowed()) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.message ??
                'This reader is unavailable. Choose another reader.',
          ),
        ),
      );
      choice = await chooseReader(context, service, title.format.name) ?? '';
      if (choice.isEmpty || !allowed()) return;
    }
  }
  if (!context.mounted || !allowed()) return;
  if (title.format == ReadingFormat.pdf) {
    await openComicReader(
      context,
      service,
      title,
      authorized: authorized,
      chooseReader: (context) => openEbookReader(
        context,
        service,
        title,
        authorized: authorized,
        choose: true,
      ),
    );
  } else {
    await openTextReader(
      context,
      service,
      title,
      authorized: authorized,
      initialLocation: initialLocation,
      openExternal: (context) => openEbookReader(
        context,
        service,
        title,
        authorized: authorized,
        choose: true,
      ),
    );
  }
}
