import 'plugin_platform.dart';

/// Installed identities and declarations only; never controllers or engines.
class PluginContribution {
  PluginContribution(this.plugin, Map<String, dynamic> definition)
    : definition = Map.unmodifiable(definition),
      id = definition['id'] as String,
      family = definition['family'] as String,
      title = definition['title'] as String,
      handler = definition['handler'] as String?;
  final PluginRecord plugin;
  final Map<String, dynamic> definition;
  final String id, family, title;
  final String? handler;
}

class ContributionRegistry {
  static const capabilities = {
    'media.descriptor': 'media.describe',
    'metadata.provider': 'metadata.provide',
    'artwork.provider': 'artwork.provide',
    'source.provider': 'sources.discover',
    'import.handler': 'import.parse',
    'export.handler': 'export.create',
    'library.tool': 'library.tools',
    'event.handler': 'events.subscribe',
    'session.hook': 'sessions.control',
    'ui.action': 'ui.present',
    'ui.section': 'ui.present',
    'ui.destination': 'ui.present',
    'settings.section': 'settings.read',
  };
  Map<String, PluginContribution> _entries = const {};
  Iterable<PluginContribution> family(String family) =>
      List.unmodifiable(_entries.values.where((c) => c.family == family));
  Iterable<PluginContribution> get all => List.unmodifiable(_entries.values);
  PluginContribution require(String id) =>
      _entries[id] ?? (throw const PluginDenied('not_found'));
  void replace(Iterable<PluginRecord> records) {
    final next = <String, PluginContribution>{};
    for (final plugin in records.where((p) => p.enabled)) {
      for (final definition in plugin.contributions) {
        final contribution = PluginContribution(plugin, definition);
        final capability = capabilities[contribution.family];
        if (capability == null || !plugin.permissions.contains(capability)) {
          continue;
        }
        if (!contribution.id.startsWith('${plugin.id}:') ||
            next.containsKey(contribution.id)) {
          throw const PluginDenied('invalid_response');
        }
        next[contribution.id] = contribution;
      }
    }
    _entries = Map.unmodifiable(next);
  }

  bool current(PluginContribution contribution) {
    final current = _entries[contribution.id];
    return current != null &&
        current.plugin.instance == contribution.plugin.instance &&
        current.plugin.revision == contribution.plugin.revision &&
        current.plugin.publisher == contribution.plugin.publisher;
  }

  List<PluginContribution> descriptorsForFile(String name) {
    final extension = name.split('.').last.toLowerCase();
    return List.unmodifiable(
      family('media.descriptor').where(
        (entry) => (entry.definition['extensions'] as List).contains(extension),
      ),
    );
  }

  void clear() => _entries = const {};
}
