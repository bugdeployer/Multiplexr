import 'dart:convert';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum AppIconRole {
  importData,
  exportData,
  openFile,
  back,
  forward,
  close,
  settings,
  play,
  pause,
  search,
  artwork,
  menu,
  library,
  spaces,
  folder,
  add,
  edit,
  delete,
  bookmark,
  next,
  previous,
  expand,
  sortAscending,
  music,
  backup,
  bookmarkSelected,
  bookmarkAdd,
  confirm,
  success,
  copy,
  newFolder,
  darkMode,
  disclosure,
  drag,
  filter,
  biometric,
  folderUnavailable,
  folderOpen,
  seekForward,
  seekBack,
  fullscreen,
  fullscreenExit,
  activity,
  info,
  collections,
  movies,
  lightMode,
  unlock,
  lock,
  metadata,
  reading,
  notifications,
  externalLink,
  palette,
  video,
  playlistAdd,
  refresh,
  repeat,
  repeatOne,
  replay,
  restore,
  save,
  selectAll,
  security,
  shuffle,
  speed,
  stop,
  subtitles,
  television,
  videoFile,
  videoLibrary,
  compactGrid,
  mute,
  volume,
  favorite,
  favoriteSelected,
}

const appIconData = <AppIconRole, IconData>{
  AppIconRole.importData: Icons.file_upload_outlined,
  AppIconRole.exportData: Icons.file_download_outlined,
  AppIconRole.openFile: Icons.file_open_outlined,
  AppIconRole.back: Icons.arrow_back,
  AppIconRole.forward: Icons.arrow_forward_rounded,
  AppIconRole.close: Icons.close,
  AppIconRole.settings: Icons.tune,
  AppIconRole.play: Icons.play_arrow,
  AppIconRole.pause: Icons.pause,
  AppIconRole.search: Icons.search,
  AppIconRole.artwork: Icons.image_outlined,
  AppIconRole.menu: Icons.more_vert,
  AppIconRole.library: Icons.grid_view,
  AppIconRole.spaces: Icons.dashboard_outlined,
  AppIconRole.folder: Icons.folder_outlined,
  AppIconRole.add: Icons.add,
  AppIconRole.edit: Icons.edit_outlined,
  AppIconRole.delete: Icons.delete_outline,
  AppIconRole.bookmark: Icons.bookmark_border,
  AppIconRole.next: Icons.skip_next,
  AppIconRole.previous: Icons.skip_previous,
  AppIconRole.expand: Icons.arrow_drop_down,
  AppIconRole.sortAscending: Icons.arrow_upward,
  AppIconRole.music: Icons.audiotrack,
  AppIconRole.backup: Icons.backup_outlined,
  AppIconRole.bookmarkSelected: Icons.bookmark,
  AppIconRole.bookmarkAdd: Icons.bookmark_add_outlined,
  AppIconRole.confirm: Icons.check,
  AppIconRole.success: Icons.check_circle,
  AppIconRole.copy: Icons.copy,
  AppIconRole.newFolder: Icons.create_new_folder_outlined,
  AppIconRole.darkMode: Icons.dark_mode_outlined,
  AppIconRole.disclosure: Icons.chevron_right,
  AppIconRole.drag: Icons.drag_handle,
  AppIconRole.filter: Icons.filter_list_rounded,
  AppIconRole.biometric: Icons.fingerprint,
  AppIconRole.folderUnavailable: Icons.folder_off_outlined,
  AppIconRole.folderOpen: Icons.folder_open_outlined,
  AppIconRole.seekForward: Icons.forward_10_rounded,
  AppIconRole.seekBack: Icons.replay_10_rounded,
  AppIconRole.fullscreen: Icons.fullscreen_rounded,
  AppIconRole.fullscreenExit: Icons.fullscreen_exit_rounded,
  AppIconRole.activity: Icons.history,
  AppIconRole.info: Icons.info_outline,
  AppIconRole.collections: Icons.layers_outlined,
  AppIconRole.movies: Icons.local_movies_outlined,
  AppIconRole.lightMode: Icons.light_mode_outlined,
  AppIconRole.unlock: Icons.lock_open_rounded,
  AppIconRole.lock: Icons.lock_outline,
  AppIconRole.metadata: Icons.manage_search,
  AppIconRole.reading: Icons.menu_book_outlined,
  AppIconRole.notifications: Icons.notifications_none_rounded,
  AppIconRole.externalLink: Icons.open_in_new,
  AppIconRole.palette: Icons.palette_outlined,
  AppIconRole.video: Icons.smart_display_outlined,
  AppIconRole.playlistAdd: Icons.queue_play_next,
  AppIconRole.refresh: Icons.refresh,
  AppIconRole.repeat: Icons.repeat,
  AppIconRole.repeatOne: Icons.repeat_one,
  AppIconRole.replay: Icons.replay,
  AppIconRole.restore: Icons.restore_rounded,
  AppIconRole.save: Icons.save_alt,
  AppIconRole.selectAll: Icons.select_all,
  AppIconRole.security: Icons.shield_outlined,
  AppIconRole.shuffle: Icons.shuffle,
  AppIconRole.speed: Icons.speed,
  AppIconRole.stop: Icons.stop,
  AppIconRole.subtitles: Icons.subtitles_outlined,
  AppIconRole.television: Icons.tv_rounded,
  AppIconRole.videoFile: Icons.video_file_outlined,
  AppIconRole.videoLibrary: Icons.video_library_outlined,
  AppIconRole.compactGrid: Icons.view_quilt_outlined,
  AppIconRole.mute: Icons.volume_off_rounded,
  AppIconRole.volume: Icons.volume_up_rounded,
  AppIconRole.favorite: Icons.favorite_border,
  AppIconRole.favoriteSelected: Icons.favorite,
};

class ThemeAsset {
  ThemeAsset(
    this.path,
    this.mime,
    this.digest,
    this.license,
    this.author,
    Uint8List bytes, {
    this.licenseText = '',
  }) : bytes = Uint8List.fromList(bytes).asUnmodifiableView();
  final String path, mime, digest, license, author;
  final Uint8List bytes;
  final String licenseText;
  static ThemeAsset parse(Map<String, dynamic> data) {
    final path = data['path'];
    if (path is! String ||
        !RegExp(r'^assets/[a-z0-9][a-z0-9_-]{0,47}\.(png|ttf|otf)$')
            .hasMatch(path)) {
      throw const FormatException('Invalid theme asset path.');
    }
    final mime = data['mime'];
    if (!['image/png', 'font/ttf', 'font/otf'].contains(mime) ||
        (mime == 'image/png'
            ? !path.endsWith('.png')
            : !path.endsWith(mime == 'font/ttf' ? '.ttf' : '.otf'))) {
      throw const FormatException('Unsupported theme asset type.');
    }
    for (final key in ['license', 'author']) {
      if (data[key] is! String ||
          (data[key] as String).trim().isEmpty ||
          (data[key] as String).length > 200) {
        throw FormatException('Theme assets need $key attribution.');
      }
    }
    final licenseText = data['licenseText'] ?? '';
    if (licenseText is! String || licenseText.length > 16384) {
      throw const FormatException('Invalid asset license text.');
    }
    final encoded = data['data'];
    if (encoded is! String || encoded.length > 1400000) {
      throw const FormatException('Theme asset too large.');
    }
    final bytes = base64Decode(encoded);
    if (bytes.isEmpty ||
        bytes.length > 1048576 ||
        sha256.convert(bytes).toString() != data['sha256']) {
      throw const FormatException('Theme asset checksum or size is invalid.');
    }
    if (mime == 'image/png') {
      if (bytes.length < 33 ||
          bytes.length > 131072 ||
          bytes.take(8).join(',') != '137,80,78,71,13,10,26,10' ||
          ascii.decode(bytes.sublist(12, 16)) != 'IHDR') {
        throw const FormatException('Invalid PNG icon.');
      }
      final header = ByteData.sublistView(bytes);
      final width = header.getUint32(16), height = header.getUint32(20);
      if (width < 1 || height < 1 || width > 256 || height > 256) {
        throw const FormatException('Icons must fit within 256 × 256.');
      }
    } else {
      if (bytes.length < 12 ||
          !['0,1,0,0', '79,84,84,79'].contains(bytes.take(4).join(','))) {
        throw const FormatException('Invalid OpenType/TrueType font.');
      }
      final header = ByteData.sublistView(bytes);
      final tables = header.getUint16(4);
      if (tables < 1 || tables > 256 || 12 + tables * 16 > bytes.length) {
        throw const FormatException('Invalid font directory.');
      }
      final tags = <String>{};
      for (var i = 0; i < tables; i++) {
        tags.add(ascii.decode(bytes.sublist(12 + i * 16, 16 + i * 16)));
        final offset = header.getUint32(12 + i * 16 + 8),
            length = header.getUint32(12 + i * 16 + 12);
        if (offset > bytes.length || length > bytes.length - offset) {
          throw const FormatException('Invalid font table.');
        }
      }
      if (!tags.containsAll(['head', 'cmap', 'maxp', 'name', 'hhea', 'hmtx']) ||
          !(tags.contains('CFF ') ||
              tags.contains('CFF2') ||
              (tags.contains('glyf') && tags.contains('loca')))) {
        throw const FormatException('Font is missing required tables.');
      }
    }
    return ThemeAsset(
      path,
      mime as String,
      data['sha256'] as String,
      data['license'],
      data['author'],
      bytes,
      licenseText: licenseText,
    );
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    'mime': mime,
    'sha256': digest,
    'license': license,
    if (licenseText.isNotEmpty) 'licenseText': licenseText,
    'author': author,
    'data': base64Encode(bytes),
  };
}

/// Validated V2 values, compiled behind existing ThemeData/component facades.
@immutable
class ThemeTokens extends ThemeExtension<ThemeTokens> {
  const ThemeTokens({
    required this.stepped,
    required this.font,
    required this.icons,
    this.radiusScale = 1,
    this.step = 3,
    this.borderWidth = 1,
    this.spacing = 1,
    this.density = 0,
    this.motionMs = 200,
    this.disabledOpacity = .38,
    this.pressedOpacity = .12,
    this.focusWidth = 2,
    this.fontScale = 1,
    this.letterSpacing = 0,
    this.buttonRadius = 16,
    this.cardRadius = 24,
    this.fieldRadius = 16,
    this.menuRadius = 18,
    this.dialogRadius = 24,
    this.elevation = 0,
    this.typography = const {},
    this.darkColors = const {},
    this.lightColors = const {},
    this.iconAssets = const {},
    this.assets = const {},
  });
  final bool stepped;
  final String font, icons;
  final double radiusScale,
      step,
      borderWidth,
      spacing,
      density,
      fontScale,
      letterSpacing;
  final double buttonRadius,
      cardRadius,
      fieldRadius,
      menuRadius,
      dialogRadius,
      elevation;
  final int motionMs;
  final double disabledOpacity, pressedOpacity, focusWidth;
  final Map<String, Map<String, num>> typography;
  final Map<String, Color> darkColors, lightColors;
  final Map<String, String> iconAssets;
  final Map<String, ThemeAsset> assets;
  String? get fontFamily => font == 'system'
      ? null
      : font == 'pixel'
      ? 'Silkscreen'
      : 'multiplexr-${assets[font]!.digest}';
  bool get pixelIcons => icons == 'pixel';

  TextStyle roleStyle(String role, TextStyle base) {
    final values = typography[role];
    return base.copyWith(
      fontFamily: fontFamily,
      fontFamilyFallback: const ['Roboto', 'Noto Sans'],
      fontSize: values?['size']?.toDouble(),
      height: values?['height']?.toDouble(),
      letterSpacing: values?['spacing']?.toDouble(),
      fontWeight: values?['weight'] == null
          ? null
          : FontWeight.values[(values!['weight']!.toInt() ~/ 100) - 1],
    );
  }

  Color? semanticColor(String role, Brightness mode) {
    final color = (mode == Brightness.dark ? darkColors : lightColors)[role];
    return role == 'playerOverlay' &&
            color != null &&
            color.computeLuminance() > .183
        ? Colors.black
        : color;
  }

  static ThemeTokens parse(
    Map<String, dynamic> data, {
    required bool retro,
    required bool pixelFont,
    Map<String, ThemeAsset> assets = const {},
  }) {
    const keys = {
      'geometry',
      'font',
      'icons',
      'radiusScale',
      'step',
      'borderWidth',
      'spacing',
      'density',
      'motionMs',
      'disabledOpacity',
      'pressedOpacity',
      'focusWidth',
      'fontScale',
      'letterSpacing',
      'buttonRadius',
      'cardRadius',
      'fieldRadius',
      'menuRadius',
      'dialogRadius',
      'elevation',
      'iconAssets',
      'typography',
      'darkColors',
      'lightColors',
    };
    if (data.keys.any((k) => !keys.contains(k))) {
      throw const FormatException('Unknown theme token.');
    }
    double number(String key, double fallback, double min, double max) {
      final value = data[key] ?? fallback;
      if (value is! num || !value.isFinite || value < min || value > max) {
        throw FormatException('Invalid $key token.');
      }
      return value.toDouble();
    }

    final geometry = data['geometry'] ?? (retro ? 'stepped' : 'rounded');
    final font = data['font'] ?? (pixelFont ? 'pixel' : 'system');
    final icons = data['icons'] ?? (retro ? 'pixel' : 'material');
    if (!['stepped', 'rounded', 'square'].contains(geometry) ||
        !['pixel', 'material'].contains(icons) ||
        (font != 'system' &&
            font != 'pixel' &&
            !(assets[font]?.mime.startsWith('font/') ?? false))) {
      throw const FormatException('Unsupported geometry, font or icon set.');
    }
    final rawIcons = data['iconAssets'] ?? <String, dynamic>{};
    if (rawIcons is! Map || rawIcons.length > AppIconRole.values.length) {
      throw const FormatException('Invalid icon roles.');
    }
    final mapped = <String, String>{};
    for (final entry in rawIcons.entries) {
      if (!AppIconRole.values.any((r) => r.name == entry.key) ||
          assets[entry.value]?.mime != 'image/png') {
        throw const FormatException('Icon role needs a packaged PNG.');
      }
      mapped[entry.key as String] = entry.value as String;
    }
    Map<String, Color> colors(String key) {
      final raw = data[key] ?? {};
      if (raw is! Map ||
          raw.keys.any(
            (k) => ![
              'surface',
              'content',
              'muted',
              'outline',
              'error',
              'selection',
              'playerOverlay',
              'card',
              'field',
              'menu',
              'dialog',
              'navigation',
              'readerChrome',
              'success',
              'warning',
            ].contains(k),
          )) {
        throw FormatException('Invalid $key roles.');
      }
      return Map.unmodifiable(
        raw.map((k, v) {
          if (v is! String || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(v)) {
            throw const FormatException('Semantic colors need #RRGGBB.');
          }
          return MapEntry(
            k as String,
            Color(0xff000000 | int.parse(v.substring(1), radix: 16)),
          );
        }),
      );
    }

    final rawType = data['typography'] ?? {};
    if (rawType is! Map ||
        rawType.keys.any(
          (k) => ![
            'heading',
            'body',
            'label',
            'metadata',
            'timestamp',
            'title',
            'caption',
            'control',
          ].contains(k),
        )) {
      throw const FormatException('Invalid typography roles.');
    }
    final typography = <String, Map<String, num>>{};
    for (final entry in rawType.entries) {
      if (entry.value is! Map) {
        throw const FormatException('Invalid typography token.');
      }
      final style = <String, num>{};
      for (final field in (entry.value as Map).entries) {
        final bounds = switch (field.key) {
          'size' => (10.0, 48.0),
          'height' => (1.0, 2.0),
          'spacing' => (-.5, 3.0),
          'weight' => (100.0, 900.0),
          _ => (1.0, 0.0),
        };
        final value = field.value;
        if (value is! num ||
            !value.isFinite ||
            value < bounds.$1 ||
            value > bounds.$2 ||
            (field.key == 'weight' && value % 100 != 0)) {
          throw const FormatException('Invalid typography value.');
        }
        style[field.key as String] = value;
      }
      typography[entry.key as String] = Map.unmodifiable(style);
    }
    return ThemeTokens(
      typography: Map.unmodifiable(typography),
      darkColors: colors('darkColors'),
      lightColors: colors('lightColors'),
      stepped: geometry == 'stepped',
      font: font as String,
      icons: icons as String,
      radiusScale: geometry == 'square' ? 0 : number('radiusScale', 1, 0, 2),
      step: number('step', 3, 1, 8),
      borderWidth: number('borderWidth', 1, .5, 3),
      spacing: number('spacing', 1, .75, 1.5),
      density: number('density', 0, -2, 2),
      motionMs: number('motionMs', 200, 0, 600).round(),
      disabledOpacity: number('disabledOpacity', .38, .3, .7),
      pressedOpacity: number('pressedOpacity', .12, .05, .25),
      focusWidth: number('focusWidth', 2, 2, 4),
      fontScale: number('fontScale', 1, .85, 1.5),
      letterSpacing: number('letterSpacing', 0, -.5, 3),
      buttonRadius: number('buttonRadius', 16, 0, 40),
      cardRadius: number('cardRadius', 24, 0, 40),
      fieldRadius: number('fieldRadius', 16, 0, 40),
      menuRadius: number('menuRadius', 18, 0, 40),
      dialogRadius: number('dialogRadius', 24, 0, 40),
      elevation: number('elevation', 0, 0, 8),
      iconAssets: Map.unmodifiable(mapped),
      assets: Map.unmodifiable(assets),
    );
  }

  bool legacyEquivalent({required bool retro, required bool pixelFont}) =>
      jsonEncode(toJson()) ==
      jsonEncode(
        ThemeTokens.parse({}, retro: retro, pixelFont: pixelFont).toJson(),
      );
  Map<String, dynamic> toJson() => {
    'geometry': stepped
        ? 'stepped'
        : radiusScale == 0
        ? 'square'
        : 'rounded',
    'font': font,
    'icons': icons,
    'radiusScale': radiusScale,
    'step': step,
    'borderWidth': borderWidth,
    'spacing': spacing,
    'density': density,
    'motionMs': motionMs,
    'disabledOpacity': disabledOpacity,
    'pressedOpacity': pressedOpacity,
    'focusWidth': focusWidth,
    'fontScale': fontScale,
    'letterSpacing': letterSpacing,
    'buttonRadius': buttonRadius,
    'cardRadius': cardRadius,
    'fieldRadius': fieldRadius,
    'menuRadius': menuRadius,
    'dialogRadius': dialogRadius,
    'elevation': elevation,
    'iconAssets': iconAssets,
    'typography': typography,
    'darkColors': darkColors.map(
      (k, v) => MapEntry(
        k,
        '#${(v.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0')}',
      ),
    ),
    'lightColors': lightColors.map(
      (k, v) => MapEntry(
        k,
        '#${(v.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0')}',
      ),
    ),
  };
  static final Map<String, Future<void>> _fonts = {};
  static final Set<String> _loadedFonts = {}, _validatedImages = {};
  Future<void> prepare() async {
    if (font != 'system' &&
        font != 'pixel' &&
        !_loadedFonts.contains(assets[font]!.digest)) {
      final asset = assets[font]!;
      if (!_fonts.containsKey(asset.digest) && _fonts.length >= 32) {
        throw const FormatException(
          'Font session limit reached. Restart before loading more fonts.',
        );
      }
      final future = _fonts[asset.digest] ??= () async {
        final loader = FontLoader(fontFamily!)
          ..addFont(Future.value(ByteData.sublistView(asset.bytes)));
        await loader.load();
      }();
      try {
        await future;
        _loadedFonts.add(asset.digest);
      } catch (_) {
        if (identical(_fonts[asset.digest], future)) {
          _fonts.remove(asset.digest);
        }
        rethrow;
      }
    }
    for (final asset in assets.values.where(
      (a) => a.mime == 'image/png' && !_validatedImages.contains(a.digest),
    )) {
      final codec = await PaintingBinding.instance
          .instantiateImageCodecWithSize(
            await ui.ImmutableBuffer.fromUint8List(asset.bytes),
          );
      try {
        if (codec.frameCount != 1) {
          throw const FormatException('Theme icons must be static PNGs.');
        }
        final frame = await codec.getNextFrame();
        frame.image.dispose();
        if (_validatedImages.length >= 2048) {
          _validatedImages.remove(_validatedImages.first);
        }
        _validatedImages.add(asset.digest);
      } finally {
        codec.dispose();
      }
    }
  }

  @override
  ThemeTokens copyWith() => this;
  @override
  ThemeTokens lerp(covariant ThemeTokens? other, double t) =>
      t < .5 ? this : other ?? this;
}
