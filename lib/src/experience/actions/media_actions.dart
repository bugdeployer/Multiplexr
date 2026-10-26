import '../../catalog/domain/classification.dart';

enum MediaActionId { settings, editMetadata, chooseArtwork, findMetadata }

class MediaActionDefinition {
  const MediaActionDefinition(this.id, this.label, this.capability);
  final MediaActionId id;
  final String label;
  final MediaCapability? capability;
}

class MediaActionContext {
  const MediaActionContext({
    required this.authorized,
    required this.capabilities,
    this.hasSettings = false,
    this.hasProvider = true,
  });
  final bool authorized, hasSettings, hasProvider;
  final Set<MediaCapability> capabilities;
}

abstract final class MediaActionRegistry {
  static const definitions = [
    MediaActionDefinition(MediaActionId.settings, 'Settings', null),
    MediaActionDefinition(MediaActionId.editMetadata, 'Edit metadata', null),
    MediaActionDefinition(
      MediaActionId.chooseArtwork,
      'Choose artwork',
      MediaCapability.artwork,
    ),
    MediaActionDefinition(
      MediaActionId.findMetadata,
      'Find metadata online',
      MediaCapability.metadataLookup,
    ),
  ];
  static bool permitted(MediaActionId id, MediaActionContext context) {
    if (!context.authorized) return false;
    final action = definitions.firstWhere((a) => a.id == id);
    if (id == MediaActionId.settings && !context.hasSettings) return false;
    if (id == MediaActionId.findMetadata && !context.hasProvider) return false;
    return action.capability == null ||
        context.capabilities.contains(action.capability);
  }

  static Future<void> execute(
    MediaActionId id,
    MediaActionContext Function() current,
    Future<void> Function() command,
  ) async {
    if (!permitted(id, current())) {
      throw StateError('This action is not available.');
    }
    await command();
  }
}
