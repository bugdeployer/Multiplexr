import '../../catalog/domain/classification.dart';
import 'media_actions.dart';

enum CatalogActionScope { collection, group, title, selection }

class CatalogActionDefinition {
  const CatalogActionDefinition(
    this.id,
    this.capability, {
    this.destructive = false,
  });
  final String id;
  final MediaCapability? capability;
  final bool destructive;
}

/// Wire aliases are compatibility adapters. Eligibility belongs to semantic IDs.
abstract final class CatalogActionRegistry {
  static const definitions = {
    'settings': CatalogActionDefinition('settings', null),
    'reset': CatalogActionDefinition('reset', null),
    'edit': CatalogActionDefinition('edit', null),
    'artwork': CatalogActionDefinition('artwork', MediaCapability.artwork),
    'find': CatalogActionDefinition('find', MediaCapability.metadataLookup),
    'tags': CatalogActionDefinition('tags', MediaCapability.tags),
    'player': CatalogActionDefinition('player', null),
    'space': CatalogActionDefinition('space', MediaCapability.localSpace),
    'select': CatalogActionDefinition('select', MediaCapability.selection),
    'selection': CatalogActionDefinition(
      'selection',
      MediaCapability.selection,
    ),
    'group': CatalogActionDefinition('group', null),
    'order': CatalogActionDefinition('order', null),
    'scan': CatalogActionDefinition('scan', MediaCapability.multipleRoots),
    'fetch': CatalogActionDefinition('fetch', MediaCapability.bulkMetadata),
    'retry': CatalogActionDefinition('retry', MediaCapability.bulkMetadata),
    'review': CatalogActionDefinition('review', MediaCapability.bulkMetadata),
    'jobs': CatalogActionDefinition('jobs', MediaCapability.bulkMetadata),
    'health': CatalogActionDefinition('health', MediaCapability.multipleRoots),
    'play': CatalogActionDefinition('play', null),
    'external': CatalogActionDefinition(
      'external',
      MediaCapability.externalEngine,
    ),
    'state': CatalogActionDefinition('state', null),
    'favorite': CatalogActionDefinition('favorite', null),
    'queue': CatalogActionDefinition('queue', null),
    'remove': CatalogActionDefinition('remove', null, destructive: true),
  };
  static const _collection = {
    'reset': 'reset',
    'settings': 'settings',
    'tags': 'tags',
    'playerSettings': 'player',
    'videoSpace': 'space',
    'cinemaSpace': 'space',
    'audioSpace': 'space',
    'select': 'select',
    'groupSeries': 'group',
    'scan': 'scan',
    'match': 'fetch',
    'fetchMetadata': 'fetch',
    'retry': 'retry',
    'retryMetadata': 'retry',
    'review': 'review',
    'reviewMetadata': 'review',
    'metadataStatus': 'jobs',
    'metadataJob': 'jobs',
    'resume': 'fetch',
    'health': 'health',
    'remove': 'remove',
  };
  static const _title = {
    'health': 'health',
    'settings': 'settings',
    'edit': 'edit',
    'artwork': 'artwork',
    'match': 'find',
    'metadata': 'find',
    'tags': 'tags',
    'internal': 'play',
    'external': 'external',
    'watched': 'state',
    'unwatched': 'state',
    'restart': 'state',
    'hide': 'state',
    'favorite': 'favorite',
    'watchLater': 'queue',
    'remove': 'remove',
  };
  static const _group = {
    'settings': 'settings',
    'metadata': 'edit',
    'edit': 'edit',
    'artwork': 'artwork',
    'order': 'order',
    'group': 'group',
    'tags': 'tags',
    'remove': 'remove',
    'internal': 'play',
    'external': 'external',
    'watched': 'state',
    'unwatched': 'state',
    'restart': 'state',
    'hide': 'state',
    'favorite': 'favorite',
    'watchLater': 'queue',
    'match': 'find',
  };
  static const _selection = {
    'selectAll': 'selection',
    'clearSelection': 'selection',
    'tagSelected': 'tags',
    'tags': 'tags',
    'metadata': 'fetch',
    'match': 'fetch',
    'watched': 'state',
    'unwatched': 'state',
    'remove': 'remove',
    'internal': 'play',
    'external': 'external',
    'favorite': 'favorite',
    'unfavorite': 'favorite',
    'watchLater': 'queue',
    'unwatchLater': 'queue',
    'clearMatches': 'find',
  };
  static CatalogActionDefinition? definition(
    CatalogActionScope scope,
    String key,
  ) =>
      definitions[(switch (scope) {
        CatalogActionScope.collection => _collection,
        CatalogActionScope.title => _title,
        CatalogActionScope.group => _group,
        CatalogActionScope.selection => _selection,
      })[key]];
  static bool permitted(
    CatalogActionScope scope,
    String key,
    MediaActionContext context,
  ) {
    final action = definition(scope, key);
    return action != null &&
        context.authorized &&
        (action.capability == null ||
            context.capabilities.contains(action.capability));
  }
}
