import '../core/application/maintenance.dart';
import '../features/reading/application/reader_choices.dart';
import '../features/settings/application/user_preferences.dart';
import '../core/persistence/local_user_preferences.dart';
import '../features/sources/application/media_imports.dart';
import '../core/platform/native_media_imports.dart';
import '../core/platform/maintenance_transport.dart';
import '../features/settings/application/navigation_preferences.dart';
import 'legacy_navigation_settings.dart';
import '../settings/domain/collection_settings_schema.dart';
import '../core/platform/library_protocol.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../core/persistence/state_repository.dart';
import '../core/platform/platform_transport.dart';
import '../core/platform/library_events.dart';
import 'library_models.dart';
import 'series.dart' show seriesIdentity;

class LibraryService
    implements
        StateStore,
        ReaderChoices,
        NavigationPreferencesHost,
        UserPreferencesHost {
  @override
  Future<List<InstalledReader>> installedReaders(String format) async {
    if (!{'epub', 'txt', 'pdf'}.contains(format)) {
      throw ArgumentError('Unsupported reader format');
    }
    final rows =
        await transport.invokeMethod<List<dynamic>>(
          'readingReaderApps',
          format,
        ) ??
        [];
    return List.unmodifiable(
      rows.map(
        (row) => InstalledReader(
          package: row['package'] as String,
          label: row['label'] as String,
        ),
      ),
    );
  }

  const LibraryService({
    PlatformTransport transport = const ChannelTransport(channel),
    this.eventHub,
    this.storageOwner,
    this.imports = const NativeMediaImports(),
    // The public parameter name is shared by platform test adapters.
    // ignore: prefer_initializing_formals
  }) : _transport = transport;
  Maintenance get maintenance => Maintenance.forOwner(persistenceOwner);
  final MediaImports imports;
  @override
  UserPreferences get userPreferences => LocalUserPreferences(this);
  @override
  NavigationPreferences get navigationPreferences =>
      NavigationPreferences(LegacyNavigationSettings(this, load: load));
  final Object? storageOwner;
  @override
  Object get persistenceOwner =>
      storageOwner ??
      (_transport is ChannelTransport
          ? _transport.persistenceOwner
          : _transport);
  final PlatformTransport _transport;
  PlatformTransport get transport =>
      MaintenanceTransport(_transport, maintenance);
  final LibraryEventHub? eventHub;
  static final events = LibraryEventHub(channel);
  Stream<ScanProgressEvent> get scanEvents => (eventHub ?? events).scanProgress;
  static const channel = MethodChannel('multiplexr/library');
  Future<Map<String, dynamic>> load() async => Map<String, dynamic>.from(
    await transport.invokeMapMethod<String, dynamic>('load') ?? {},
  );
  Future<void> writeVideoProgress(Map<String, dynamic> progress) =>
      transport.invokeMethod('writeVideoProgress', jsonEncode(progress));
  @override
  Future<Map<String, dynamic>?> readState(String key) async {
    final value = await transport.invokeMethod<String>('readState', key);
    return value == null ? null : decodeState(value);
  }

  Future<Map<String, Map<String, dynamic>?>> readStates(
    List<String> keys,
  ) async {
    final result = <String, Map<String, dynamic>?>{};
    for (var offset = 0; offset < keys.length; offset += 400) {
      final batch = keys.skip(offset).take(400).toList();
      final raw = await transport.invokeMethod<String>('readStates', batch);
      final values = Map<String, dynamic>.from(jsonDecode(raw ?? '{}'));
      for (final key in batch) {
        result[key] = values[key] == null
            ? null
            : Map<String, dynamic>.from(values[key]);
      }
    }
    return result;
  }

  @override
  Future<void> writeState(String key, Map<String, dynamic>? value) => transport
      .invokeMethod('writeState', StateWriteRequest(key, value).toWire());
  Future<void> editTags(
    List<VideoAsset> assets, {
    required String operation,
    required List<String> tags,
    String? target,
    String? collectionId,
  }) => transport.invokeMethod('editTags', {
    'assets': assets
        .map((a) => {'collectionId': a.collectionId, 'id': a.id})
        .toList(),
    'operation': operation,
    'tags': tags,
    'target': target,
    'collectionId': collectionId,
  });
  Future<void> saveGrouping(List<VideoAsset> assets) => transport.invokeMethod(
    'saveGrouping',
    jsonEncode(assets.map((a) => a.toJson()).toList()),
  );
  Future<bool> exportBackup() async =>
      await transport.invokeMethod<bool>('exportBackup') ?? false;
  Future<String?> readBackup() => transport.invokeMethod<String>('readBackup');
  Future<void> restoreBackup(String json) =>
      transport.invokeMethod('restoreBackup', json);

  Future<LibraryRoot?> pickRoot() async {
    final data = await transport.invokeMapMethod<String, dynamic>('pickRoot');
    return data == null ? null : LibraryRoot.fromJson(data);
  }

  Future<void> saveQueue(List<String> queue) =>
      transport.invokeMethod('saveQueue', queue);
  Future<void> saveSeriesIndex(Map<String, dynamic> index) =>
      transport.invokeMethod('saveSeriesIndex', jsonEncode(index));
  Future<void> updateFlags(
    List<VideoAsset> assets,
    String action,
    bool value,
  ) => transport.invokeMethod('updateFlags', {
    'assets': assets
        .map((a) => {'id': a.id, 'collectionId': a.collectionId})
        .toList(),
    'action': action,
    'value': value,
  });
  Future<void> saveBrowsing(String id, Map<String, dynamic> values) {
    CollectionSettingsSchema.validate(values, browsingOnly: true);
    return transport.invokeMethod('saveBrowsing', {'id': id, 'values': values});
  }

  Future<void> saveCollection(VideoCollection collection) =>
      transport.invokeMethod('saveCollection', jsonEncode(collection.toJson()));
  Future<void> releaseRoots(List<String> uris) =>
      transport.invokeMethod('releaseRoots', uris);
  Future<void> removeCollection(String id) =>
      transport.invokeMethod('removeCollection', id);
  Future<List<String>> scan(String id, {String? requestId}) async {
    final raw = await transport.invokeMethod<Object>(
      'scan',
      requestId == null ? id : {'id': id, 'requestId': requestId},
    );
    if (requestId == null) return List<String>.from(raw as List? ?? []);
    if (raw is! Map ||
        raw['requestId'] != requestId ||
        raw['warnings'] is! List) {
      throw const FormatException('Scan response identity mismatch.');
    }
    return List<String>.from(raw['warnings']);
  }

  Future<void> cancelScan(String id) =>
      transport.invokeMethod('cancelScan', id);
  Future<void> watchState(VideoAsset asset, String action) =>
      transport.invokeMethod('watchState', {
        'collectionId': asset.collectionId,
        'id': asset.id,
        'action': action,
      });
  Future<void> saveAsset(VideoAsset asset, {bool preserveTags = false}) =>
      transport.invokeMethod(
        preserveTags ? 'saveMatchedAsset' : 'saveAsset',
        jsonEncode(asset.toJson()),
      );
  Future<void> applyMetadataPatch(
    VideoAsset before,
    VideoAsset after,
    Set<String> selected,
  ) async {
    final fields = <String, dynamic>{};
    final expected = <String, dynamic>{};
    for (final key in selected) {
      final top = {'poster', 'backdrop', 'seriesBackdrop'}.contains(key);
      final wire = top ? key : 'metadata.$key';
      fields[wire] = top ? after.toJson()[key] : after.metadata[key];
      expected[wire] = top ? before.toJson()[key] : before.metadata[key];
    }
    for (final key in [
      'providerId',
      'metadataSource',
      'metadataStatus',
      'seriesId',
      'episodeId',
    ]) {
      if (after.toJson()[key] == before.toJson()[key]) continue;
      fields[key] = after.toJson()[key];
      expected[key] = before.toJson()[key];
    }
    expected.putIfAbsent('metadataSource', () => before.metadataSource);
    expected['filename'] = before.filename;
    expected['relativePath'] = before.relativePath;
    expected['rootUri'] = before.rootUri;
    await transport.invokeMethod(
      'applyMetadata',
      jsonEncode({
        'id': before.id,
        'collectionId': before.collectionId,
        'fields': fields,
        'expected': expected,
        if (seriesIdentity(before) case final String anchor)
          'groupAnchor': anchor,
        if (before.metadataSource == 'filename') 'inferred': before.metadata,
      }),
    );
  }

  Future<void> position(VideoAsset asset, int milliseconds) =>
      transport.invokeMethod('position', {
        'collectionId': asset.collectionId,
        'id': asset.id,
        'positionMs': milliseconds,
        'durationMs': asset.durationMs,
      });
  Future<void> external(VideoAsset asset) =>
      transport.invokeMethod('external', asset.uri);
}
