import 'fixtures/legacy_library_assembly.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/media/audiobook_metadata.dart';

import 'media_foundation_test.dart' show SharedStore;
import 'grouped_media_test.dart' show audiobook;

void main() {
  testWidgets(
    'standalone metadata lookup requires an installed provider without legacy I/O',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const channel = MethodChannel('multiplexr/audio');
      final calls = <Map>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'metadataDbConfigured') return false;
        final args = Map.from(call.arguments as Map);
        calls.add(args);
        return jsonEncode(
          args['page'] == 1
              ? [
                  {'title': 'The Primal Hunter', 'providerId': 'B09MWP4277'},
                ]
              : [],
        );
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AudiobookMetadataSearchPage(
            library: createAudioLibrary(SharedStore()),
            book: audiobook('Primal Hunter'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No enabled metadata providers'),
        findsOneWidget,
      );
      expect(calls, isEmpty);
    },
  );
}
