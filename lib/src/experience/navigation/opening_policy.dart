import '../../settings/domain/media_settings.dart';

enum OpeningDestination { contents, details, session, denied, unavailable }

class OpeningPolicy {
  const OpeningPolicy();
  OpeningDestination resolve({
    required bool group,
    required TitleOpenAction action,
    bool explicitPlay = false,
    bool authorized = true,
    bool available = true,
  }) {
    if (!authorized) return OpeningDestination.denied;
    if (group) return OpeningDestination.contents;
    if (!explicitPlay && action == TitleOpenAction.details) {
      return OpeningDestination.details;
    }
    return available
        ? OpeningDestination.session
        : OpeningDestination.unavailable;
  }

  static TitleOpenAction legacyAction(
    String value, {
    required bool legacyDetails,
  }) => switch (value) {
    'details' => TitleOpenAction.details,
    'play' => TitleOpenAction.play,
    _ => legacyDetails ? TitleOpenAction.details : TitleOpenAction.play,
  };
}
