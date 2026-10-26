import '../settings/domain/collection_settings_schema.dart';

import 'package:app_shell/app_shell.dart';

import '../media/navigation_settings.dart';

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'library_models.dart';
import 'library_controller.dart';
import '../media/contracts.dart';

Future<VideoCollection?> collectionDialog(
  BuildContext context,
  LibraryController library, {
  VideoCollection? existing,
  String? initialSection,
  Set<String> readingNames = const {},
  Future<void> Function(Map<String, dynamic>, Map<String, dynamic>)?
  saveReading,
}) => existing != null
    ? Navigator.push<VideoCollection>(
        context,
        MaterialPageRoute(
          builder: (_) => CollectionForm(
            library: library,
            existing: existing,
            initialSection: initialSection,
          ),
        ),
      )
    : showModalBottomSheet<VideoCollection>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (_) => CollectionForm(
          library: library,
          existing: existing,
          initialSection: initialSection,
          saveReading: saveReading,
          readingNames: readingNames,
        ),
      );

class CollectionForm extends StatefulWidget {
  const CollectionForm({
    super.key,
    required this.library,
    this.existing,
    this.initialSection,
    this.saveReading,
    this.readingNames = const {},
    this.readingExisting,
    this.readingPreferences = const {},
    this.removeReading,
    this.readerSettings,
  });
  final LibraryController library;
  final VideoCollection? existing;
  final Map<String, dynamic>? readingExisting;
  final Map<String, dynamic> readingPreferences;
  final Future<void> Function()? removeReading;
  final VoidCallback? readerSettings;

  final String? initialSection;
  final Set<String> readingNames;
  final Future<void> Function(Map<String, dynamic>, Map<String, dynamic>)?
  saveReading;
  @override
  State<CollectionForm> createState() => _CollectionFormState();
}

class _CollectionFormState extends State<CollectionForm> {
  final sectionKeys = {'Playback': GlobalKey()};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = sectionKeys[widget.initialSection]?.currentContext;
      if (mounted && target != null) Scrollable.ensureVisible(target);
    });
  }

  bool get editing => widget.existing != null || widget.readingExisting != null;
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(
    text: widget.existing?.name ?? widget.readingExisting?['name'] as String?,
  );
  final extension = TextEditingController();
  late VideoSubtype subtype = widget.existing?.subtype ?? VideoSubtype.videos;
  late MediaKind kind = widget.existing?.kind ?? MediaKind.video;
  late bool includeInGlobalAudio =
      widget.existing?.includeInGlobalAudio ?? true;
  late MediaType mediaType = widget.readingExisting != null
      ? MediaType.ebook
      : kind == MediaKind.video
      ? MediaType.video
      : MediaType.audio;
  late MediaSubtype readingSubtype = widget.readingExisting == null
      ? MediaSubtype.ebook
      : MediaSubtype.values.byName(
          widget.readingExisting!['subtype'] as String,
        );
  bool get reading => mediaType == MediaType.ebook;
  bool get audio => !reading && kind != MediaKind.video;
  late final readingFormats = <MediaSubtype, Set<String>>{
    MediaSubtype.ebook:
        widget.readingExisting?['subtype'] == 'ebook' &&
            widget.readingPreferences['formats'] != null
        ? (widget.readingPreferences['formats'] as List).cast<String>().toSet()
        : {'epub', 'txt', 'pdf'},
    MediaSubtype.comics:
        widget.readingExisting?['subtype'] == 'comics' &&
            widget.readingPreferences['formats'] != null
        ? (widget.readingPreferences['formats'] as List).cast<String>().toSet()
        : {'cbz', 'images'},
  };
  late bool includeInGlobalReading =
      widget.readingExisting?['includeInGlobal'] as bool? ?? true;

  late CatalogView view = widget.readingExisting != null
      ? switch (widget.readingPreferences['layout']) {
          'list' => CatalogView.list,
          'compact' => CatalogView.compact,
          _ => CatalogView.grid,
        }
      : {
          CatalogView.netflix,
          CatalogView.posterWall,
        }.contains(widget.existing?.view)
      ? CatalogView.grid
      : widget.existing?.view ?? CatalogView.grid;
  late PlaybackTarget player =
      widget.existing?.player ?? PlaybackTarget.internal;
  late final roots = [
    ...?widget.existing?.roots,
    for (final r in widget.readingExisting?['roots'] as List? ?? [])
      LibraryRoot(r['uri'] as String, r['name'] as String),
  ];
  late final extensions = {
    ...widget.existing?.extensions ??
        const ['mp4', 'mkv', 'mov', 'webm', 'm4v'],
  };
  late final touchedRoots = roots.map((r) => r.uri).toSet();
  late bool locked =
      widget.existing?.locked ??
      widget.readingExisting?['locked'] as bool? ??
      false;
  late bool includeInGlobalCinema =
      widget.existing?.includeInGlobalCinema ?? true;
  late bool includeInGlobalVideos =
      widget.existing?.includeInGlobalVideos ?? true;
  late bool autoplayNext = widget.existing?.autoplayNext ?? false;
  late double cardSize =
      widget.existing?.cardSize ??
      (widget.readingPreferences['cardSize'] as num?)?.toDouble() ??
      180;
  late bool allowFolders = widget.existing?.allowFolders ?? false;
  late String openAction =
      widget.existing?.openAction ??
      (widget.readingPreferences['openAction'] == 'open' ? 'play' : 'details');
  late double audioRate = widget.existing?.audioRate ?? 1;
  bool busy = false;
  String? error, extensionError;
  Set<String> get selectedExtensions =>
      reading ? readingFormats[readingSubtype]! : extensions;
  Set<String> get supportedReadingExtensions =>
      readingSubtype == MediaSubtype.ebook
      ? {'epub', 'txt', 'pdf'}
      : {'cbz', 'images'};
  void addExtension() {
    final raw = extension.text.trim().toLowerCase().replaceFirst(
      RegExp(r'^\.+'),
      '',
    );
    if (raw.isEmpty) return;
    final value =
        reading &&
            readingSubtype == MediaSubtype.comics &&
            {'jpg', 'jpeg', 'png', 'webp'}.contains(raw)
        ? 'images'
        : raw;
    setState(() {
      if (reading && !supportedReadingExtensions.contains(value)) {
        extensionError = readingSubtype == MediaSubtype.ebook
            ? 'The reader supports .epub, .txt and .pdf.'
            : 'The reader supports .cbz and JPEG/PNG/WebP image chapters.';
        return;
      }
      selectedExtensions.add(value);
      extension.clear();
      extensionError = null;
    });
  }

  @override
  void dispose() {
    widget.library
        .releaseRoots(touchedRoots.toList())
        .catchError((Object _) {});
    name.dispose();
    extension.dispose();
    super.dispose();
  }

  Future<void> pick() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final root = await widget.library.pickRoot();
      if (mounted && root != null && !roots.any((r) => r.uri == root.uri)) {
        setState(() {
          roots.add(root);
          touchedRoots.add(root.uri);
        });
      }
    } on PlatformException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    if (reading
        ? readingFormats[readingSubtype]!.isEmpty
        : extensions.isEmpty) {
      setState(() => error = 'Select at least one file type.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    if (locked !=
        (widget.existing?.locked ??
            widget.readingExisting?['locked'] as bool? ??
            false)) {
      try {
        if (!await widget.library.authenticate()) {
          if (mounted) {
            setState(() {
              busy = false;
              error =
                  'Authentication cancelled. Collection lock was not changed.';
            });
          }
          return;
        }
        if (!mounted) return;
        if (widget.existing != null) {
          widget.library.authorizeCollection(widget.existing!.id);
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            busy = false;
            error = 'Set up a device screen lock, then authenticate to change collection lock.';
          });
        }
        return;
      }
    }
    if (reading) {
      final id =
          widget.readingExisting?['id'] as String? ??
          'reading-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
      try {
        await widget.saveReading!(
          {
            'id': id,
            'name': name.text.trim(),
            'subtype': readingSubtype.name,
            'locked': locked,
            'includeInGlobal': includeInGlobalReading,
            'roots': [
              for (final root in roots) {'uri': root.uri, 'name': root.name},
            ],
          },
          {
            'layout': view == CatalogView.list
                ? 'list'
                : view == CatalogView.compact
                ? 'compact'
                : 'grid',
            if (!editing) 'sort': 'title',
            'openAction': openAction == 'play' ? 'open' : 'details',
            'cardSize': cardSize,
            'formats': readingFormats[readingSubtype]!.toList()..sort(),
          },
        );
        if (mounted) Navigator.pop(context);
      } catch (_) {
        if (mounted) {
          setState(() => error = 'Could not save the collection. Try again.');
        }
      } finally {
        if (mounted) setState(() => busy = false);
      }
      return;
    }
    final collection = VideoCollection(
      id:
          widget.existing?.id ??
          '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}',
      name: name.text.trim(),
      kind: kind,
      includeInGlobalAudio: includeInGlobalAudio,
      subtype: subtype,
      view: view,
      player: player,
      openAction: openAction,
      audioRate: audioRate,
      allowFolders: allowFolders,
      cardSize: cardSize,
      autoplayNext: autoplayNext,
      locked: locked,
      includeInGlobalCinema: includeInGlobalCinema,
      includeInGlobalVideos: includeInGlobalVideos,
      roots: roots,
      extensions: extensions.toList()..sort(),
    );
    try {
      final saved = VideoCollection.fromJson({
        ...?widget.existing?.toJson(),
        ...collection.toJson(),
        if (editing) ...{
          for (final key in [
            'sort',
            'filter',
            'scrollOffset',
            'folder',
            'lastScanAt',
            'rootHealth',
          ])
            key: widget.existing!.toJson()[key],
        },
      });
      final normalized = VideoCollection.fromJson({
        ...saved.toJson(),
        if (subtype == VideoSubtype.videos &&
            ['movies', 'tv'].contains(saved.filter))
          'filter': 'all',
        if (!allowFolders) 'folder': '',
        if (allowFolders != widget.existing?.allowFolders ||
            subtype != widget.existing?.subtype)
          'scrollOffset': 0.0,
      });
      await widget.library.save(normalized);
      if (mounted) Navigator.pop(context, normalized);
    } on PlatformException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not save the collection. Try again.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> removeCollection() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove collection?'),
        content: const Text(
          'This removes the collection and its index. Your source files stay in their folders.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove collection'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (reading) {
        await widget.removeReading!();
      } else {
        await widget.library.remove(widget.existing!.id);
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'Could not remove the collection. Try again.';
        });
      }
    }
  }

  Widget section(String title) => Padding(
    key: sectionKeys[title],
    padding: EdgeInsets.only(
      top: title == 'General' && editing ? 0 : 24,
      bottom: 16,
    ),
    child: Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) =>
      PopScope(canPop: !busy, child: page(context));

  Widget page(BuildContext context) => !editing
      ? ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .92,
          ),
          child: contents(context),
        )
      : Scaffold(
          appBar: AppBar(title: const Text('Collection settings')),
          body: SafeArea(top: false, child: contents(context)),
        );

  Widget contents(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      24,
      16,
      24,
      MediaQuery.viewInsetsOf(context).bottom +
          (View.of(context).viewPadding.bottom /
              View.of(context).devicePixelRatio) +
          24,
    ),
    child: Form(
      key: form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!editing)
            Row(
              children: [
                Expanded(
                  child: Text(
                    !editing ? 'New collection' : 'Collection settings',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: busy ? null : () => Navigator.pop(context),
                  tooltip: 'Close',
                  icon: const AppIcon(AppIconRole.close),
                ),
              ],
            ),
          section('General'),
          DropdownButtonFormField<MediaType>(
            icon: const AppIcon(AppIconRole.expand),
            isExpanded: true,
            initialValue: mediaType,
            decoration: const InputDecoration(labelText: 'Media type'),
            items: [
              for (final type in MediaType.values.where(
                (t) =>
                    appSubtypes.forType(t).isNotEmpty &&
                    (t != MediaType.ebook || widget.saveReading != null),
              ))
                DropdownMenuItem(
                  value: type,
                  child: Text(switch (type) {
                    MediaType.video => 'Video',
                    MediaType.audio => 'Audio',
                    MediaType.photo => 'Photo',
                    MediaType.ebook => 'Ebook',
                  }),
                ),
            ],
            onChanged: busy || editing
                ? null
                : (value) async {
                    setState(() {
                      mediaType = value!;
                      if (reading) {
                        if (!{
                          CatalogView.grid,
                          CatalogView.list,
                          CatalogView.compact,
                        }.contains(view)) {
                          view = CatalogView.grid;
                        }
                        return;
                      }
                      kind = value == MediaType.audio
                          ? MediaKind.audiobook
                          : MediaKind.video;
                      if (audio && view == CatalogView.netflix) {
                        view = CatalogView.grid;
                      }
                      extensions
                        ..clear()
                        ..addAll(
                          audio
                              ? [
                                  'mp3',
                                  'm4b',
                                  'm4a',
                                  'flac',
                                  'ogg',
                                  'opus',
                                  'wav',
                                  'aac',
                                ]
                              : ['mp4', 'mkv', 'mov', 'webm', 'm4v'],
                        );
                    });
                  },
          ),
          if (reading) ...[
            const AppGap(16),
            DropdownButtonFormField<MediaSubtype>(
              isExpanded: true,
              key: const ValueKey('reading-subtype'),
              initialValue: readingSubtype,
              icon: const AppIcon(AppIconRole.expand),
              decoration: const InputDecoration(labelText: 'Subtype'),
              items: const [
                DropdownMenuItem(
                  value: MediaSubtype.ebook,
                  child: Text('Ebooks'),
                ),
                DropdownMenuItem(
                  value: MediaSubtype.comics,
                  child: Text('Comics'),
                ),
              ],
              onChanged: busy || editing
                  ? null
                  : (value) => setState(() {
                      readingSubtype = value!;
                      extensionError = null;
                    }),
            ),
            const AppGap(8),
            Text(
              'Metadata: title, authors, description, language, identifier${readingSubtype == MediaSubtype.comics ? ', comic style' : ''}.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (audio) ...[
            const AppGap(16),
            DropdownButtonFormField<AudioSubtype>(
              isExpanded: true,
              icon: const AppIcon(AppIconRole.expand),
              initialValue: kind == MediaKind.music
                  ? AudioSubtype.music
                  : AudioSubtype.audiobooks,
              decoration: const InputDecoration(labelText: 'Subtype'),
              items: [
                const DropdownMenuItem(
                  value: AudioSubtype.audiobooks,
                  child: Text('Audiobooks'),
                ),
                DropdownMenuItem(
                  value: AudioSubtype.music,
                  enabled: appSubtypes.definition(MediaSubtype.music).enabled,
                  child: Text(
                    appSubtypes.definition(MediaSubtype.music).enabled
                        ? 'Music'
                        : 'Music (not available yet)',
                  ),
                ),
              ],
              onChanged: busy || editing
                  ? null
                  : (value) => setState(() {
                      kind = value == AudioSubtype.music
                          ? MediaKind.music
                          : MediaKind.audiobook;
                    }),
            ),
          ],
          if (!audio && !reading) ...[
            const AppGap(16),
            DropdownButtonFormField<VideoSubtype>(
              isExpanded: true,
              icon: const AppIcon(AppIconRole.expand),
              initialValue: subtype,
              decoration: const InputDecoration(labelText: 'Subtype'),
              items: [VideoSubtype.videos, VideoSubtype.cinema]
                  .map((v) => DropdownMenuItem(value: v, child: Text(v.label)))
                  .toList(),
              onChanged: busy ? null : (v) => setState(() => subtype = v!),
            ),
            const AppGap(8),
            Text(
              'Metadata: ${metadataFields[subtype]!.values.join(', ').toLowerCase()}.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const AppGap(20),
          TextFormField(
            controller: name,
            maxLength: 80,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Collection name',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Enter a collection name.';
              }
              if (widget.readingNames.contains(value.trim().toLowerCase()) ||
                  widget.library.collections.any(
                    (c) =>
                        c.id != widget.existing?.id &&
                        c.name.toLowerCase() == value.trim().toLowerCase(),
                  )) {
                return 'A collection with this name already exists.';
              }
              return null;
            },
          ),
          section('Sources'),
          Text('Root folders', style: Theme.of(context).textTheme.titleMedium),
          const AppGap(8),
          Text(
            reading && readingSubtype == MediaSubtype.comics
                ? 'Includes subfolders. Selected CBZ archives and image chapters are indexed.'
                : 'Includes subfolders. Only selected file types are indexed.',
          ),
          if (audio && kind == MediaKind.audiobook)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Use Series name / Audiobook title / audio files. A standalone title also has its own series.',
              ),
            ),
          const AppGap(12),
          for (final root in roots) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const AppIcon(AppIconRole.folder),
              title: Text(root.name),
              trailing: IconButton(
                tooltip: 'Remove ${root.name}',
                onPressed: busy
                    ? null
                    : () => setState(() => roots.remove(root)),
                icon: const AppIcon(AppIconRole.close),
              ),
            ),
            if (!reading && !audio && subtype == VideoSubtype.cinema)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 16),
                child: DropdownButtonFormField<VideoSubtype>(
                  isExpanded: true,
                  icon: const AppIcon(AppIconRole.expand),
                  key: ValueKey('content-${root.uri}'),
                  initialValue: root.contentSubtype ?? VideoSubtype.movies,
                  decoration: InputDecoration(
                    labelText: 'Content in ${root.name}',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: VideoSubtype.movies,
                      child: Text('Movies'),
                    ),
                    DropdownMenuItem(
                      value: VideoSubtype.tv,
                      child: Text('TV shows'),
                    ),
                  ],
                  onChanged: busy
                      ? null
                      : (value) => setState(() {
                          final index = roots.indexOf(root);
                          roots[index] = LibraryRoot(
                            root.uri,
                            root.name,
                            contentSubtype: value,
                          );
                        }),
                ),
              ),
          ],
          const AppGap(8),
          OutlinedButton.icon(
            onPressed: busy ? null : pick,
            icon: const AppIcon(AppIconRole.newFolder),
            label: const Text('Add root folder'),
          ),
          const AppGap(24),
          Text(
            'Allowed file types',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const AppGap(8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                {
                      ...reading
                          ? (readingSubtype == MediaSubtype.ebook
                                ? const ['epub', 'txt', 'pdf']
                                : const ['cbz', 'images'])
                          : audio
                          ? const [
                              'mp3',
                              'm4a',
                              'm4b',
                              'aac',
                              'flac',
                              'ogg',
                              'oga',
                              'opus',
                              'wav',
                            ]
                          : const [
                              'mp4',
                              'mkv',
                              'mov',
                              'webm',
                              'm4v',
                              'avi',
                              'ts',
                              'm2ts',
                              '3gp',
                            ],
                      ...reading ? readingFormats[readingSubtype]! : extensions,
                    }
                    .map(
                      (e) => FilterChip(
                        label: Text(
                          e == 'images'
                              ? 'Image chapters (JPEG/PNG/WebP)'
                              : '.$e',
                        ),
                        selected:
                            (reading
                                    ? readingFormats[readingSubtype]!
                                    : extensions)
                                .contains(e),
                        onSelected: busy
                            ? null
                            : (v) => setState(() {
                                if (v) {
                                  (reading
                                          ? readingFormats[readingSubtype]!
                                          : extensions)
                                      .add(e);
                                } else {
                                  (reading
                                          ? readingFormats[readingSubtype]!
                                          : extensions)
                                      .remove(e);
                                }
                              }),
                      ),
                    )
                    .toList(),
          ),
          const AppGap(16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: extension,
                  maxLength: 10,
                  decoration: InputDecoration(
                    labelText: 'Other extension',
                    counterText: '',
                    errorText: extensionError,
                    helperMaxLines: 3,
                    errorMaxLines: 3,
                    helperText: reading
                        ? (readingSubtype == MediaSubtype.ebook
                              ? 'Supported: .epub, .txt, .pdf'
                              : 'Supported: .cbz, JPEG/PNG/WebP image chapters')
                        : null,
                  ),
                  enabled: !busy,
                  onSubmitted: busy ? null : (_) => addExtension(),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Add extension',
                onPressed: busy ? null : addExtension,
                icon: const AppIcon(AppIconRole.add),
              ),
            ],
          ),
          if (roots.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'You can create an empty collection and add folders later.',
              ),
            ),
          ...[
            section('Access & privacy'),
            InterfaceSwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(CollectionSettingsSchema.field('locked').label),
              subtitle: const Text(
                'Require device authentication to open. Relocks in the background; hidden from global spaces.',
              ),
              value: locked,
              onChanged: busy
                  ? null
                  : (value) => setState(() => locked = value),
            ),
            InterfaceSwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                reading
                    ? 'Include in global ${readingSubtype == MediaSubtype.ebook ? 'Ebooks' : 'Comics'}'
                    : audio
                    ? 'Include in global ${kind == MediaKind.music ? 'Music' : 'Audiobooks'}'
                    : subtype == VideoSubtype.videos
                    ? 'Include in global Videos'
                    : 'Include in global cinema',
              ),
              subtitle: Text(
                locked
                    ? 'Locked collections stay private, regardless of this preference.'
                    : reading
                    ? 'Show this collection in the combined ${readingSubtype == MediaSubtype.ebook ? 'Ebooks' : 'Comics'} space'
                    : audio
                    ? 'Show this collection in the combined ${kind == MediaKind.music ? 'Music' : 'Audiobooks'} space'
                    : subtype == VideoSubtype.videos
                    ? 'Show this collection in the combined Videos space'
                    : 'Show this collection in the combined Movies & TV space',
              ),
              value: reading
                  ? includeInGlobalReading
                  : audio
                  ? includeInGlobalAudio
                  : subtype == VideoSubtype.videos
                  ? includeInGlobalVideos
                  : includeInGlobalCinema,
              onChanged: busy
                  ? null
                  : (value) => setState(() {
                      if (reading) {
                        includeInGlobalReading = value;
                      } else if (audio) {
                        includeInGlobalAudio = value;
                      } else if (subtype == VideoSubtype.videos) {
                        includeInGlobalVideos = value;
                      } else {
                        includeInGlobalCinema = value;
                      }
                    }),
            ),
          ],
          section('Appearance'),
          DropdownButtonFormField<CatalogView>(
            isExpanded: true,
            icon: const AppIcon(AppIconRole.expand),
            initialValue: view,
            decoration: InputDecoration(
              labelText: CollectionSettingsSchema.field('view').label,
            ),
            items: [
              for (final mode in const [
                CatalogView.grid,
                CatalogView.list,
                CatalogView.compact,
              ])
                DropdownMenuItem(value: mode, child: Text(mode.label)),
            ],
            onChanged: busy ? null : (v) => setState(() => view = v!),
          ),
          const AppGap(20),
          Text(CollectionSettingsSchema.field('cardSize').label),
          Slider(
            value: cardSize.clamp(120, 280),
            min: 120,
            max: 280,
            divisions: 4,
            label: '${cardSize.round()}',
            onChanged: busy ? null : (v) => setState(() => cardSize = v),
          ),
          if (!reading)
            InterfaceSwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(CollectionSettingsSchema.field('allowFolders').label),
              subtitle: const Text('Show folders in normal collection views'),
              value: allowFolders,
              onChanged: busy ? null : (v) => setState(() => allowFolders = v),
            ),
          section('Navigation'),
          TitleOpeningControl(
            value: openAction,
            immediateLabel: reading ? 'Open immediately' : 'Play immediately',
            showAutomatic: !reading,
            onChanged: busy
                ? null
                : (value) => setState(() => openAction = value),
          ),
          if (reading) ...[
            section('Reader'),
            if (widget.readerSettings != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Reader settings'),
                subtitle: const Text(
                  'Collection defaults and inherited values',
                ),
                trailing: const AppIcon(AppIconRole.disclosure),
                onTap: widget.readerSettings,
              )
            else
              const Text(
                'Multiplexr reader. Reader settings inherit your application defaults and can be changed after creation.',
              ),
          ] else ...[
            section('Playback'),
            if (audio && kind == MediaKind.audiobook)
              InterfaceSwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  CollectionSettingsSchema.field('autoplayNext').label,
                ),
                subtitle: const Text(
                  'Continue with the next audiobook in this series after the current audiobook finishes.',
                ),
                value: autoplayNext,
                onChanged: busy
                    ? null
                    : (value) => setState(() => autoplayNext = value),
              ),
            ...[
              if (audio && kind == MediaKind.audiobook) const AppGap(16),
              DropdownButtonFormField<PlaybackTarget>(
                isExpanded: true,
                icon: const AppIcon(AppIconRole.expand),
                initialValue: player,
                decoration: InputDecoration(
                  labelText: CollectionSettingsSchema.field('player').label,
                ),
                items: const [
                  DropdownMenuItem(
                    value: PlaybackTarget.internal,
                    child: Text('Multiplexr player'),
                  ),
                  DropdownMenuItem(
                    value: PlaybackTarget.external,
                    child: Text('External player'),
                  ),
                ],
                onChanged: busy ? null : (v) => setState(() => player = v!),
              ),
              if (!audio && subtype != VideoSubtype.videos)
                InterfaceSwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Autoplay next episode'),
                  subtitle: const Text(
                    'Play the next available local episode after completion',
                  ),
                  value: autoplayNext,
                  onChanged: busy
                      ? null
                      : (v) => setState(() => autoplayNext = v),
                ),
            ],
          ],
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const AppGap(24),
          FilledButton(
            onPressed: busy ? null : save,
            child: Text(
              busy
                  ? 'Working…'
                  : !editing
                  ? 'Create collection'
                  : 'Save collection',
            ),
          ),
          if (editing) ...[
            const AppGap(32),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Danger zone',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            ),
            const Text(
              'Removing this collection deletes its index and saved history. Source files are kept.',
            ),
            const AppGap(12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
                side: BorderSide(color: Theme.of(context).colorScheme.error),
              ),
              onPressed: busy ? null : removeCollection,
              icon: const AppIcon(AppIconRole.delete),
              label: const Text('Remove collection'),
            ),
          ],
        ],
      ),
    ),
  );
}
