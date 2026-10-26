import 'host_settings.dart';

import 'dart:convert';

import '../../../settings/domain/media_settings.dart';
import '../../../experience/navigation/opening_policy.dart';
import '../../../library/library_models.dart';

abstract interface class NavigationPreferencesHost {
  NavigationPreferences get navigationPreferences;
}

class NavigationValues {
  const NavigationValues({this.openAction = 'automatic', this.rate = 0});
  final String openAction;
  final double rate;
  String resolveAction(String inherited) =>
      openAction == 'automatic' ? inherited : openAction;
  SettingsLayer layer(SettingsScope scope, String id) =>
      SettingsLayer(scope, id, {
        'opening': switch (openAction) {
          'details' => const SettingOverride.value(TitleOpenAction.details),
          'play' => const SettingOverride.value(TitleOpenAction.play),
          _ => const SettingOverride.inherit(),
        },
        'rate': rate.isFinite && rate >= .5 && rate <= 3
            ? SettingOverride.value(rate)
            : const SettingOverride.inherit(),
      });
  Map<String, dynamic> toJson() => {'openAction': openAction, 'rate': rate};
  static double validRate(Object? value) =>
      value is num && value.isFinite && value >= .5 && value <= 3
      ? value.toDouble()
      : 0;
  static String key(String collectionId, String entityId) =>
      'media:settings:${jsonEncode([collectionId, entityId])}';
}

class EffectiveMediaNavigation {
  const EffectiveMediaNavigation(
    this.opening,
    this.rate,
    this.engine,
    this.autoplayNext,
  );
  final ResolvedSetting<TitleOpenAction> opening;
  final ResolvedSetting<double> rate;
  final ResolvedSetting<EngineSelection> engine;
  final ResolvedSetting<bool> autoplayNext;
  OpeningDestination destination({
    bool group = false,
    bool forcePlay = false,
    bool authorized = true,
    bool available = true,
  }) => const OpeningPolicy().resolve(
    group: group,
    action: opening.value,
    explicitPlay: forcePlay,
    authorized: authorized,
    available: available,
  );
}

abstract interface class NavigationSettingsStore {
  Future<Map<String, dynamic>?> read(String key);
  Future<void> merge(String key, Map<String, dynamic> values);
  Future<VideoCollection?> collection(String id);
}

class NavigationPreferences {
  const NavigationPreferences(this.store);
  final NavigationSettingsStore store;
  Future<NavigationValues> read(String key) async {
    final value = await store.read(key);
    return NavigationValues(
      openAction: ['details', 'play'].contains(value?['openAction'])
          ? value!['openAction']
          : 'automatic',
      rate: NavigationValues.validRate(value?['rate']),
    );
  }

  Future<void> save(String key, NavigationValues value) {
    HostSettings.validate('navigation', value.toJson());
    return store.merge(key, value.toJson());
  }

  Future<EffectiveMediaNavigation> parentForKey(
    String key,
    Iterable<String> ancestors,
  ) async {
    final identity =
        jsonDecode(key.substring('media:settings:'.length)) as List;
    return resolve(
      collection: await store.collection(identity[0] as String),
      collectionId: identity[0] as String,
      titleId: '',
      ancestorIds: ancestors,
      includeTitle: false,
    );
  }

  Future<EffectiveMediaNavigation> resolve({
    required VideoCollection? collection,
    required String collectionId,
    Iterable<String> ancestorIds = const [],
    required String titleId,
    bool legacyDetails = false,
    bool includeTitle = true,
  }) async {
    final layers = <SettingsLayer>[
      SettingsLayer(SettingsScope.collection, collectionId, {
        'engine': SettingOverride.value(
          collection?.player == PlaybackTarget.external
              ? EngineSelection.external
              : EngineSelection.internal,
        ),
        'autoplayNext': SettingOverride.value(
          collection?.autoplayNext ?? false,
        ),
        'opening': collection == null || collection.openAction == 'automatic'
            ? const SettingOverride.inherit()
            : SettingOverride.value(
                OpeningPolicy.legacyAction(
                  collection.openAction,
                  legacyDetails: legacyDetails,
                ),
              ),
        if (collection != null &&
            NavigationValues.validRate(collection.audioRate) > 0)
          'rate': SettingOverride.value(collection.audioRate),
      }),
    ];
    for (final ancestor in ancestorIds) {
      layers.add(
        (await read(NavigationValues.key(collectionId, ancestor)))
            .layer(SettingsScope.group, ancestor),
      );
    }
    if (includeTitle) {
      layers.add(
        (await read(NavigationValues.key(collectionId, titleId)))
            .layer(SettingsScope.title, titleId),
      );
    }
    const resolver = SettingsResolver();
    return EffectiveMediaNavigation(
      resolver.resolve(
        MediaSettings.opening,
        layers,
        fallback: legacyDetails
            ? TitleOpenAction.details
            : TitleOpenAction.play,
      ),
      resolver.resolve(MediaSettings.rate, layers),
      resolver.resolve(MediaSettings.engine, layers),
      resolver.resolve(MediaSettings.autoplayNext, layers),
    );
  }
}
