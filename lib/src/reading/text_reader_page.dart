import 'reading_text_source.dart';

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../experience/navigation/navigation_coordinator.dart';
import 'reader_host.dart';

import 'package:app_shell/app_shell.dart';

import 'domain/reader_adapter.dart';
import 'domain/reading_annotations.dart';
import 'domain/reading_catalog.dart';
import 'domain/reading_location.dart';
import '../features/reading/application/reading_annotations.dart';
import '../features/reading/application/reading_session.dart';
import 'text_reader_controller.dart';
import 'text_reader_layout.dart';
import 'text_reader_settings.dart';

/// Opens the text adapter through the shared navigation/session owners.
Future<void> openTextReader(
  BuildContext context,
  ReaderHost service,
  ReadingTitle title, {
  required bool Function(String) authorized,
  Map<String, String> validatedFonts = const {},
  TextReadingLocation? initialLocation,
  Future<void> Function(BuildContext)? openExternal,
}) => NavigationCoordinator.forOwner(service.persistenceOwner).run(
  'reader:${title.catalog.id.collectionId}:${title.catalog.id.entityId}',
  () async {
    if (!authorized(title.catalog.id.collectionId) || !context.mounted) return;
    final tokens = Theme.of(context).extension<ThemeTokens>();
    final fonts = <String, String>{
      ...validatedFonts,
      if (tokens != null && tokens.fontFamily != null)
        tokens.font: tokens.fontFamily!,
    };
    final reader = service.text();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TextReaderPage(
          title: title,
          controller: reader.controller,
          session: reader.session,
          annotations: reader.annotations,
          validatedFonts: fonts,
          initialLocation: initialLocation,
          openExternal: openExternal,
        ),
      ),
    );
  },
);

class TextReaderPage extends StatefulWidget {
  const TextReaderPage({
    super.key,
    required this.title,
    required this.controller,
    required this.session,
    required this.annotations,
    this.validatedFonts = const {},
    this.initialLocation,
    this.openExternal,
  });
  final Future<void> Function(BuildContext)? openExternal;
  final TextReadingLocation? initialLocation;
  final ReadingTitle title;
  final TextReaderController controller;
  final ReadingSession session;
  final ReadingAnnotations annotations;
  final Map<String, String> validatedFonts;
  @override
  State<TextReaderPage> createState() => _TextReaderPageState();
}

class _TextReaderPageState extends State<TextReaderPage>
    with WidgetsBindingObserver {
  final _scroll = ScrollController();
  Timer? _saveTimer;
  Future<void> _saving = Future.value();
  bool _ready = false,
      _opening = true,
      _closing = false,
      _allowPop = false,
      _chrome = true;
  Object? _openError;
  String? _saveError, _notesError;
  List<ReadingAnnotation> _annotations = [];
  int _windowStart = 0, _windowEnd = 0;
  String _layoutKey = '';
  (String, int)? _returnPosition;
  double? _scrub;
  TextSelection _selection = const TextSelection.collapsed(offset: 0);
  TextReaderLayout? _layout;
  double _width = 1, _height = 1;
  bool _adjustingScroll = false;
  static int _annotationSequence = 0;
  TextReaderController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.addListener(_changed);
    _scroll.addListener(_scrolled);
    unawaited(_open());
  }

  Future<void> _open({bool restart = false}) async {
    if (mounted) {
      setState(() {
        _opening = true;
        _openError = null;
      });
    }
    try {
      await widget.session.open(
        widget.title,
        restart: restart,
        recovered: restart ? null : widget.initialLocation,
      );
      if (!mounted) return;
      try {
        _annotations = (await widget.annotations.read())
            .where((a) => a.title == widget.title.catalog.id)
            .toList();
      } catch (_) {
        _notesError =
            'Could not load saved notes. Retry in Bookmarks and notes.';
      }
      if (mounted) {
        setState(() {
          _ready = true;
          _opening = false;
          _windowStart = c.offset;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _opening = false;
          _openError = error;
        });
      }
    }
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (_ready && !_closing && !c.loading) {
      _saveTimer?.cancel();
      _saveTimer = Timer(
        const Duration(milliseconds: 700),
        () => unawaited(_persist()),
      );
    }
  }

  Future<bool> _persist() async {
    if (!_ready || widget.session.state != ReaderSessionState.open) return true;
    var success = false;
    final next = _saving.then((_) async {
      try {
        await widget.session.save();
        success = true;
        if (mounted && _saveError != null) setState(() => _saveError = null);
      } catch (_) {
        if (mounted) {
          setState(
            () => _saveError =
                'Could not save your position. Retry before leaving.',
          );
        }
      }
    });
    _saving = next;
    await next;
    return success;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _saveTimer?.cancel();
      unawaited(_persist());
    }
  }

  Future<void> _leave({bool discard = false}) async {
    if (_closing) return;
    setState(() => _closing = true);
    _saveTimer?.cancel();
    try {
      await _saving;
      if (discard || !_ready) {
        await widget.session.discard();
      } else {
        await widget.session.close();
      }
      if (!mounted) return;
      setState(() => _allowPop = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _closing = false;
          _saveError = 'Could not save your position. Retry before leaving.';
        });
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is PlatformException
                  ? error.message ?? 'This action is unavailable.'
                  : 'Could not complete this action. Try again.',
            ),
          ),
        );
      }
    }
  }

  void _resetWindow() {
    _segmentKeys.clear();
    _windowStart = c.offset;
    _layoutKey = '';
    _selection = const TextSelection.collapsed(offset: 0);
    if (_scroll.hasClients) {
      _adjustingScroll = true;
      _scroll.jumpTo(0);
      _adjustingScroll = false;
    }
    if (mounted) setState(() {});
  }

  Future<void> _jump(String resource, int offset, {String? anchor}) async {
    if (!await _persist()) return;
    final previous = (c.resourceId, c.offset);
    await c.jump(resource, offset, anchor: anchor);
    _returnPosition = previous;
    _resetWindow();
  }

  Future<void> _turn(bool forward) async {
    if (c.loading || _layout == null) return;
    if (!await _persist()) return;
    final text = c.content!.text;
    final index = c.title.readingOrder.indexWhere((r) => r.id == c.resourceId);
    if (forward && _windowEnd < text.length) {
      c.setOffset(_windowEnd);
    } else if (!forward && _windowStart > 0) {
      c.setOffset(_layout!.pageBefore(_windowStart, _width, _height));
    } else if (forward && index + 1 < c.title.readingOrder.length) {
      await c.jump(c.title.readingOrder[index + 1].id, 0);
    } else if (!forward && index > 0) {
      await c.jump(c.title.readingOrder[index - 1].id, 0);
      c.setOffset(
        _layoutFor(c.content!)
            .pageBefore(c.content!.text.length, _width, _height),
      );
    }
    _resetWindow();
  }

  void _scrolled() {
    if (_adjustingScroll ||
        !_ready ||
        c.preferences['textMode'] != 'scroll' ||
        _layout == null ||
        !_scroll.hasClients) {
      return;
    }
    final painter = _layout!.painter(_windowStart, _windowEnd, _width);
    var anchor =
        _windowStart +
        painter.getPositionForOffset(Offset(0, _scroll.offset)).offset;
    painter.dispose();
    if (c.content!.elements.any(
      (e) =>
          e['kind'] == 'image' &&
          (e['offset'] as int) >= _windowStart &&
          (e['offset'] as int) < _windowEnd,
    )) {
      anchor = _windowStart;
      final viewport = _scroll.position.context.storageContext
          .findRenderObject();
      if (viewport is RenderBox) {
        final top = viewport.localToGlobal(Offset.zero).dy;
        for (final entry
            in _segmentKeys.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key))) {
          final box = entry.value.currentContext?.findRenderObject();
          if (box is! RenderBox || !box.attached) continue;
          final relative = box.localToGlobal(Offset.zero).dy - top;
          if (relative + box.size.height <= 0) continue;
          final end = c.content!.elements
              .where(
                (e) => e['kind'] == 'image' && (e['offset'] as int) > entry.key,
              )
              .map((e) => e['offset'] as int)
              .fold<int>(_windowEnd, math.min);
          final segment = _layout!.painter(entry.key, end, _width);
          anchor =
              entry.key +
              segment
                  .getPositionForOffset(Offset(0, math.max(0, -relative)))
                  .offset;
          segment.dispose();
          break;
        }
      }
    }
    c.setOffset(anchor, notify: false);
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 700),
      () => unawaited(_persist()),
    );
    if (_scroll.position.extentAfter < _height * .6 &&
        _windowEnd < c.content!.text.length) {
      if (_windowEnd - _windowStart < TextReaderLayout.maxWindow * 3) {
        setState(
          () => _windowEnd = TextReaderController.safeOffset(
            c.content!.text,
            math.min(
              c.content!.text.length,
              _windowEnd + TextReaderLayout.maxWindow,
            ),
          ),
        );
      } else {
        setState(() {
          _windowStart = c.offset;
          _windowEnd = TextReaderController.safeOffset(
            c.content!.text,
            math.min(
              c.content!.text.length,
              _windowStart + TextReaderLayout.maxWindow * 2,
            ),
          );
        });
        _adjustingScroll = true;
        _scroll.jumpTo(0);
        _adjustingScroll = false;
      }
    } else if (_scroll.offset <= 1 && _windowStart > 0) {
      final old = _windowStart;
      final next = TextReaderController.safeOffset(
        c.content!.text,
        math.max(0, old - TextReaderLayout.maxWindow),
      );
      final p = _layout!.painter(next, old, _width);
      final shift = p.height;
      p.dispose();
      setState(() {
        _windowStart = next;
        _windowEnd = math.min(
          _windowEnd,
          next + TextReaderLayout.maxWindow * 3,
        );
      });
      _adjustingScroll = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(shift);
        _adjustingScroll = false;
      });
    }
  }

  TextReaderLayout _layoutFor(ReadingTextResource resource) {
    final prefs = c.preferences;
    final palette = ReaderPalette.resolve(prefs, Theme.of(context).colorScheme);
    final font = prefs['fontAsset'] as String;
    final family =
        widget.validatedFonts[font] ??
        switch (font) {
          'serif' => 'serif',
          'sans' => 'sans-serif',
          'monospace' => 'monospace',
          _ => 'sans-serif',
        };
    return TextReaderLayout(
      resource,
      TextStyle(
        inherit: false,
        color: palette.foreground,
        fontSize: (prefs['fontSize'] as num).toDouble(),
        height: (prefs['lineHeight'] as num).toDouble(),
        fontFamily: family,
        fontWeight: FontWeight.values[(prefs['fontWeight'] as int) ~/ 100 - 1],
      ),
      MediaQuery.textScalerOf(context),
      Directionality.of(context),
      switch (prefs['alignment']) {
        'justify' => TextAlign.justify,
        'center' => TextAlign.center,
        _ => TextAlign.start,
      },
      (prefs['paragraphSpacing'] as num).toDouble(),
      annotations: _annotations
          .where(
            (a) =>
                a.matches(c.title) &&
                a.resourceId == c.resourceId &&
                a.kind != ReadingAnnotationKind.bookmark &&
                a.end <= resource.text.length &&
                resource.text.substring(a.start, a.end) == a.quote,
          )
          .toList(),
    );
  }

  Future<void> _markFinished(bool finished) async {
    final previous = widget.session.finished;
    final operation = _saving.then(
      (_) => widget.session.save(finished: finished),
    );
    _saving = operation.catchError((Object _) {});
    await operation;
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(finished ? 'Marked finished' : 'Marked unread'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => _run(() => _markFinished(previous)),
        ),
      ),
    );
  }

  Future<void> _contents() async {
    final entries = await c.contents();
    if (!mounted) return;
    final selected = await showDialog<ReadingContentsEntry>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Contents'),
        children: [
          SizedBox(
            width: 400,
            height: MediaQuery.sizeOf(context).height * .6,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: entries.length,
              itemBuilder: (context, i) {
                final r = entries[i];
                return ListTile(
                  selected: r.resourceId == c.resourceId,
                  title: Text(r.label.isEmpty ? 'Chapter ${i + 1}' : r.label),
                  onTap: () => Navigator.pop(context, r),
                );
              },
            ),
          ),
        ],
      ),
    );
    if (selected != null) {
      await _jump(selected.resourceId, 0, anchor: selected.anchor);
    }
  }

  Future<void> _search() async {
    final result = await Navigator.of(context).push<ReadingSearchResult>(
      MaterialPageRoute(
        builder: (_) =>
            ReadingTextSearchPage(source: c.source, search: c.search),
      ),
    );
    if (result != null) await _jump(result.resourceId, result.offset);
  }

  Future<void> _add(ReadingAnnotationKind kind) async {
    final text = c.content!.text;
    final start = kind == ReadingAnnotationKind.bookmark
        ? c.offset
        : _windowStart + _selection.start;
    final end = kind == ReadingAnnotationKind.bookmark
        ? start
        : _windowStart + _selection.end;
    if (start < 0 ||
        end > text.length ||
        end - start > 4096 ||
        kind != ReadingAnnotationKind.bookmark && start == end) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select up to 4,096 characters first.')),
      );
      return;
    }
    Future<void> save(String note) async {
      final annotation = ReadingAnnotation(
        id: 'annotation-${DateTime.now().microsecondsSinceEpoch}-${_annotationSequence++}',
        title: c.title.catalog.id,
        sourceId: c.title.catalog.sources.single.id,
        sourceRevision: c.title.sourceRevision,
        resourceId: c.resourceId,
        start: start,
        end: end,
        quote: text.substring(start, end),
        before: text.substring(math.max(0, start - 40), start),
        after: text.substring(end, math.min(text.length, end + 40)),
        kind: kind,
        note: note,
        label: kind == ReadingAnnotationKind.bookmark
            ? text.substring(start, math.min(text.length, start + 80))
            : '',
      );
      await widget.annotations.save(annotation);
      await _refreshAnnotations();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${kind == ReadingAnnotationKind.note
                  ? 'Note'
                  : kind == ReadingAnnotationKind.highlight
                  ? 'Highlight'
                  : 'Bookmark'} saved',
            ),
          ),
        );
      }
    }

    if (kind == ReadingAnnotationKind.note) {
      await showDialog<void>(
        context: context,
        builder: (_) => _ReaderNoteDialog(save: save),
      );
    } else {
      await save('');
    }
  }

  Future<void> _refreshAnnotations() async {
    final items = await widget.annotations.read();
    _notesError = null;
    if (mounted) {
      setState(
        () => _annotations = items
            .where((a) => a.title == widget.title.catalog.id)
            .toList(),
      );
    }
  }

  Future<void> _saved() async {
    await _refreshAnnotations();
    if (!mounted) return;
    final selected = await showDialog<ReadingAnnotation>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SimpleDialog(
          title: const Text('Bookmarks and notes'),
          children: [
            SizedBox(
              width: 400,
              height: MediaQuery.sizeOf(context).height * .6,
              child: _annotations.isEmpty
                  ? const Center(
                      child: Text('No saved bookmarks or notes yet.'),
                    )
                  : ListView.builder(
                      itemCount: _annotations.length,
                      itemBuilder: (context, i) {
                        final a = _annotations[i];
                        final matches = a.matches(c.title);
                        return ListTile(
                          title: Text(
                            a.kind == ReadingAnnotationKind.bookmark
                                ? a.label.isEmpty
                                      ? 'Bookmark'
                                      : a.label
                                : a.quote,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            !matches
                                ? 'Source changed; saved note retained'
                                : a.note.isNotEmpty
                                ? a.note
                                : a.kind.name,
                          ),
                          onTap: matches
                              ? () => Navigator.pop(context, a)
                              : null,
                          trailing: Wrap(
                            children: [
                              if (a.kind == ReadingAnnotationKind.note)
                                IconButton(
                                  tooltip: 'Edit note',
                                  icon: const AppIcon(AppIconRole.edit),
                                  onPressed: () => _run(() async {
                                    await showDialog<void>(
                                      context: context,
                                      builder: (_) => _ReaderNoteDialog(
                                        initial: a.note,
                                        save: (value) async {
                                          await widget.annotations.save(
                                            ReadingAnnotation.fromJson({
                                              ...a.toJson(),
                                              'note': value,
                                            }),
                                          );
                                          await _refreshAnnotations();
                                        },
                                      ),
                                    );
                                    update(() {});
                                  }),
                                ),
                              IconButton(
                                tooltip: 'Delete saved item',
                                icon: const AppIcon(AppIconRole.delete),
                                onPressed: () => _run(() async {
                                  await widget.annotations.remove(a);
                                  await _refreshAnnotations();
                                  update(() {});
                                  if (mounted) {
                                    ScaffoldMessenger.of(
                                      this.context,
                                    ).showSnackBar(
                                      SnackBar(
                                        content: const Text(
                                          'Saved item removed',
                                        ),
                                        action: SnackBarAction(
                                          label: 'Undo',
                                          onPressed: () => _run(() async {
                                            await widget.annotations.save(a);
                                            await _refreshAnnotations();
                                          }),
                                        ),
                                      ),
                                    );
                                  }
                                }),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
    if (selected != null) await _jump(selected.resourceId, selected.start);
  }

  final _segmentKeys = <int, GlobalKey>{};
  Widget _selectable(int start, int end) => SelectableText.rich(
    _layout!.span(start, end),
    key: ValueKey('${c.resourceId}:$start'),
    textAlign: _layout!.align,
    textScaler: MediaQuery.textScalerOf(context),
    onTap: () => setState(() => _chrome = !_chrome),
    onSelectionChanged: (selection, _) => _selection = TextSelection(
      baseOffset: selection.baseOffset < 0
          ? -1
          : start - _windowStart + selection.baseOffset,
      extentOffset: selection.extentOffset < 0
          ? -1
          : start - _windowStart + selection.extentOffset,
    ),
    contextMenuBuilder: (context, editable) =>
        AdaptiveTextSelectionToolbar.buttonItems(
          anchors: editable.contextMenuAnchors,
          buttonItems: [
            ...editable.contextMenuButtonItems,
            ContextMenuButtonItem(
              label: 'Highlight',
              onPressed: () {
                editable.hideToolbar();
                unawaited(_run(() => _add(ReadingAnnotationKind.highlight)));
              },
            ),
            ContextMenuButtonItem(
              label: 'Add note',
              onPressed: () {
                editable.hideToolbar();
                unawaited(_run(() => _add(ReadingAnnotationKind.note)));
              },
            ),
            for (final action in ['dictionary', 'share'])
              ContextMenuButtonItem(
                label: action == 'dictionary' ? 'Dictionary' : 'Share',
                onPressed: () {
                  final selected = c.content!.text.substring(
                    _windowStart + _selection.start,
                    _windowStart + _selection.end,
                  );
                  editable.hideToolbar();
                  unawaited(_run(() => c.source.textAction(action, selected)));
                },
              ),
          ],
        ),
  );

  Widget _publicationContent() {
    final images =
        c.content!.elements
            .where(
              (e) =>
                  e['kind'] == 'image' &&
                  (e['offset'] as int) >= _windowStart &&
                  (e['offset'] as int) < _windowEnd,
            )
            .toList()
          ..sort((a, b) => (a['offset'] as int).compareTo(b['offset'] as int));
    if (images.isEmpty) return _selectable(_windowStart, _windowEnd);
    final children = <Widget>[];
    var start = _windowStart;
    for (final image in images) {
      final offset = image['offset'] as int;
      if (offset > start) {
        children.add(
          KeyedSubtree(
            key: _segmentKeys.putIfAbsent(start, GlobalKey.new),
            child: _selectable(start, offset),
          ),
        );
      }
      if (c.source is ReadingImages) {
        children.add(
          _PublicationIllustration(
            key: ValueKey('${c.resourceId}:${image['href']}'),
            source: c.source as ReadingImages,
            resource: c.resourceId,
            href: image['href'] as String,
            label: image['label'] as String,
          ),
        );
      }
      start = offset;
    }
    if (start < _windowEnd) {
      children.add(
        KeyedSubtree(
          key: _segmentKeys.putIfAbsent(start, GlobalKey.new),
          child: _selectable(start, _windowEnd),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Future<void> _followLink(Map<String, dynamic> link) async {
    final resource = c.title.readingOrder.firstWhere(
      (r) => r.id == c.resourceId,
    );
    final target = Uri.parse(resource.href).resolve(link['href'] as String);
    if (target.hasScheme || target.hasAuthority || target.hasQuery) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This link leaves the publication. Open it in an external reader.',
            ),
          ),
        );
      }
      return;
    }
    final next = c.title.readingOrder
        .where((r) => Uri.parse(r.href).path == target.path)
        .firstOrNull;
    if (next == null) {
      if (c.source is! ReadingLinkedResources) {
        throw StateError('This linked resource is unavailable.');
      }
      final note = await (c.source as ReadingLinkedResources).linkedResource(
        c.resourceId,
        link['href'] as String,
      );
      if (!mounted) return;
      final start = note.anchors[target.fragment] ?? 0;
      final following =
          note.anchors.values.where((offset) => offset > start).toList()
            ..sort();
      final end = math.min(
        following.firstOrNull ?? note.text.length,
        start + 32000,
      );
      final palette = ReaderPalette.resolve(
        c.preferences,
        Theme.of(context).colorScheme,
      );
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: palette.background,
        builder: (sheet) => FractionallySizedBox(
          heightFactor: .65,
          child: Column(
            children: [
              ListTile(
                title: Text(
                  'Linked note',
                  style: TextStyle(color: palette.foreground),
                ),
                trailing: IconButton(
                  tooltip: 'Return to reading',
                  onPressed: () => Navigator.pop(sheet),
                  icon: AppIcon(AppIconRole.close, color: palette.foreground),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: AppSpacing.of(context).all(24),
                  child: SelectableText.rich(_layoutFor(note).span(start, end)),
                ),
              ),
            ],
          ),
        ),
      );
      return;
    }
    await _jump(next.id, 0, anchor: target.fragment);
  }

  @override
  Widget build(BuildContext context) {
    final palette = _ready
        ? ReaderPalette.resolve(c.preferences, Theme.of(context).colorScheme)
        : ReaderPalette(
            Theme.of(context).colorScheme.surface,
            Theme.of(context).colorScheme.onSurface,
          );
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        backgroundColor: palette.background,
        appBar: _chrome || !_ready
            ? AppBar(
                leading: IconButton(
                  tooltip: 'Back',
                  onPressed: _closing ? null : () => _leave(),
                  icon: const AppIcon(AppIconRole.back),
                ),
                title: Text(widget.title.catalog.title),
                actions: [
                  if (_ready) ...[
                    IconButton(
                      tooltip: 'Contents',
                      onPressed: () => _run(_contents),
                      icon: const AppIcon(AppIconRole.playlistAdd),
                    ),
                    IconButton(
                      tooltip: 'Bookmarks and notes',
                      onPressed: () => _run(_saved),
                      icon: const AppIcon(AppIconRole.bookmarkSelected),
                    ),
                    IconButton(
                      tooltip: 'Search publication',
                      onPressed: () => _run(_search),
                      icon: const AppIcon(AppIconRole.search),
                    ),
                    IconButton(
                      tooltip: 'Reader settings',
                      onPressed: () => _run(() async {
                        await showTextReaderSettings(
                          context,
                          c,
                          widget.validatedFonts,
                        );
                        _resetWindow();
                      }),
                      icon: const AppIcon(AppIconRole.settings),
                    ),
                    PopupMenuButton<String>(
                      icon: const AppIcon(AppIconRole.menu),
                      tooltip: 'Reader actions',
                      onSelected: (value) => _run(switch (value) {
                        'contents' => _contents,
                        'saved' => _saved,
                        'save' => () async {
                          await _persist();
                        },
                        _ => () async {
                          await _markFinished(!widget.session.finished);
                        },
                      }),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'contents',
                          child: Text('Contents'),
                        ),
                        PopupMenuItem(
                          value: 'saved',
                          child: Text('Bookmarks and notes'),
                        ),
                        PopupMenuItem(
                          value: 'save',
                          child: Text('Save position'),
                        ),
                        PopupMenuItem(
                          value: 'finished',
                          child: Text(
                            widget.session.finished
                                ? 'Mark unread'
                                : 'Mark finished',
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              )
            : null,
        body: SafeArea(
          child: Column(
            children: [
              if (_notesError != null)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .2,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        Text(_notesError!),
                        TextButton(
                          onPressed: () => _run(_refreshAnnotations),
                          child: const Text('Retry notes'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_saveError != null)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .3,
                  ),
                  child: SingleChildScrollView(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          children: [
                            Text(_saveError!),
                            Wrap(
                              children: [
                                TextButton(
                                  onPressed: () => _persist(),
                                  child: const Text('Retry'),
                                ),
                                if (widget.openExternal != null)
                                  TextButton.icon(
                                    icon: const AppIcon(
                                      AppIconRole.externalLink,
                                    ),
                                    label: const Text('Open with…'),
                                    onPressed: () => _run(
                                      () => widget.openExternal!(context),
                                    ),
                                  ),
                                TextButton(
                                  onPressed: () => _leave(discard: true),
                                  child: const Text('Leave without saving'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: _opening || _ready && c.content == null
                    ? const Center(child: CircularProgressIndicator())
                    : !_ready
                    ? Center(
                        child: SingleChildScrollView(
                          padding: AppSpacing.of(context).all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _openError is ReadingRecoveryRequired ||
                                        _openError is TextLocationRecovery
                                    ? 'The saved position needs recovery. Your progress and notes are retained.'
                                    : 'Could not open this publication. Check its source and folder access.',
                              ),
                              TextButton(
                                onPressed: () => _open(),
                                child: const Text('Retry'),
                              ),
                              if (_openError is ReadingRecoveryRequired ||
                                  _openError is TextLocationRecovery)
                                TextButton(
                                  onPressed: () => _open(restart: true),
                                  child: const Text('Start from beginning'),
                                ),
                            ],
                          ),
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, bounds) {
                          final margin = math.min(
                            (c.preferences['margin'] as num).toDouble(),
                            math.max(0, (bounds.maxWidth - 80) / 2),
                          );
                          _width = math.max(1, bounds.maxWidth - margin * 2);
                          _height = math.max(1, bounds.maxHeight - 16);
                          _layout = _layoutFor(c.content!);
                          final layoutKey =
                              '${c.resourceId}:${c.preferences.hashCode}:$_width:$_height:${MediaQuery.textScalerOf(context)}';
                          if (_layoutKey != layoutKey) {
                            _windowStart = c.offset;
                            _windowEnd = 0;
                            _layoutKey = layoutKey;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted && _scroll.hasClients) {
                                _adjustingScroll = true;
                                _scroll.jumpTo(0);
                                _adjustingScroll = false;
                              }
                            });
                          }
                          final scrolling =
                              c.preferences['textMode'] == 'scroll';
                          if (!scrolling) {
                            _windowEnd = _layout!.pageEnd(
                              _windowStart,
                              _width,
                              _height,
                            );
                          } else if (_windowEnd <= _windowStart) {
                            _windowEnd = TextReaderController.safeOffset(
                              c.content!.text,
                              math.min(
                                c.content!.text.length,
                                _windowStart + TextReaderLayout.maxWindow * 2,
                              ),
                            );
                          }
                          return GestureDetector(
                            onHorizontalDragEnd: scrolling
                                ? null
                                : (details) {
                                    if (!_selection.isCollapsed ||
                                        c.loading ||
                                        details.primaryVelocity == null ||
                                        details.primaryVelocity!.abs() < 150) {
                                      return;
                                    }
                                    unawaited(
                                      _run(
                                        () => _turn(
                                          Directionality.of(context) ==
                                                  TextDirection.rtl
                                              ? details.primaryVelocity! > 0
                                              : details.primaryVelocity! < 0,
                                        ),
                                      ),
                                    );
                                  },
                            child: Stack(
                              children: [
                                Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: margin.toDouble(),
                                    vertical: 8,
                                  ),
                                  child: SingleChildScrollView(
                                    controller: _scroll,
                                    child: SizedBox(
                                      width: _width,
                                      child: c.content!.text.isEmpty
                                          ? const Text(
                                              'This chapter has no text.',
                                            )
                                          : _publicationContent(),
                                    ),
                                  ),
                                ),
                                if (c.loading)
                                  const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              if (_ready && _chrome && c.content != null) ...[
                if (c.content!.elements.any(
                  (e) =>
                      e['kind'] == 'link' &&
                      (e['offset'] as int) >= _windowStart &&
                      (e['offset'] as int) < _windowEnd,
                ))
                  SizedBox(
                    height: 48,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final link in c.content!.elements.where(
                          (e) =>
                              e['kind'] == 'link' &&
                              (e['offset'] as int) >= _windowStart &&
                              (e['offset'] as int) < _windowEnd,
                        ))
                          TextButton.icon(
                            onPressed: () => _run(() => _followLink(link)),
                            icon: const AppIcon(AppIconRole.externalLink),
                            label: Text(
                              (link['label'] as String).isEmpty
                                  ? 'Follow link'
                                  : link['label'] as String,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                if (_returnPosition != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const AppIcon(AppIconRole.replay),
                      label: const Text('Return to reading position'),
                      onPressed: () => _run(() async {
                        final position = _returnPosition!;
                        await c.jump(position.$1, position.$2);
                        _returnPosition = null;
                        _resetWindow();
                      }),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Reading: ${c.title.readingOrder.where((r) => r.id == c.resourceId).firstOrNull?.label ?? c.title.catalog.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
                Slider(
                  semanticFormatterCallback: (value) =>
                      '${(value * 100).round()} percent of chapter',
                  value:
                      (_scrub ??
                              (c.content!.text.isEmpty
                                  ? 0
                                  : c.offset / c.content!.text.length))
                          .clamp(0.0, 1.0),
                  onChanged: c.loading
                      ? null
                      : (value) => setState(() => _scrub = value),
                  onChangeEnd: (value) => _run(() async {
                    final offset = TextReaderController.safeOffset(
                      c.content!.text,
                      (value * c.content!.text.length).round(),
                    );
                    _scrub = null;
                    await _jump(c.resourceId, offset);
                  }),
                ),
              ],
              if (_ready && _chrome)
                Row(
                  children: [
                    PopupMenuButton<String>(
                      tooltip: 'Contents and settings',
                      icon: const AppIcon(AppIconRole.reading),
                      onSelected: (value) => _run(
                        value == 'contents'
                            ? _contents
                            : () async {
                                await showTextReaderSettings(
                                  context,
                                  c,
                                  widget.validatedFonts,
                                );
                                _resetWindow();
                              },
                      ),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'contents',
                          child: Text('Contents'),
                        ),
                        PopupMenuItem(
                          value: 'settings',
                          child: Text('Reader settings'),
                        ),
                      ],
                    ),
                    IconButton(
                      tooltip: 'Previous page',
                      onPressed: c.loading
                          ? null
                          : () => _run(() => _turn(false)),
                      icon: const AppIcon(AppIconRole.back),
                    ),
                    Expanded(
                      child: Text(
                        'Chapter ${c.title.readingOrder.indexWhere((r) => r.id == c.resourceId) + 1} of ${c.title.readingOrder.length} · ${c.content == null || c.content!.text.isEmpty ? 0 : (100 * c.offset / c.content!.text.length).round()}%',
                        textAlign: TextAlign.center,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Add bookmark',
                      onPressed: c.loading
                          ? null
                          : () => _run(
                              () => _add(ReadingAnnotationKind.bookmark),
                            ),
                      icon: const AppIcon(AppIconRole.bookmark),
                    ),
                    IconButton(
                      tooltip: 'Next page',
                      onPressed: c.loading
                          ? null
                          : () => _run(() => _turn(true)),
                      icon: const AppIcon(AppIconRole.forward),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    c.removeListener(_changed);
    _scroll.dispose();
    unawaited(
      _saving.then((_) => widget.session.discard()).catchError((Object _) {}),
    );
    c.dispose();
    super.dispose();
  }
}

class _ReaderNoteDialog extends StatefulWidget {
  const _ReaderNoteDialog({required this.save, this.initial = ''});
  final Future<void> Function(String) save;
  final String initial;
  @override
  State<_ReaderNoteDialog> createState() => _ReaderNoteDialogState();
}

class _ReaderNoteDialogState extends State<_ReaderNoteDialog> {
  late final _input = TextEditingController(text: widget.initial);
  bool _busy = false;
  String? _error;
  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.save(_input.text);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not save this note. Your draft is retained.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add note'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _input,
            autofocus: true,
            maxLength: 4096,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Note'),
          ),
          if (_error != null) Text(_error!),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _busy ? null : _save, child: const Text('Save')),
    ],
  );
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }
}

class ReadingTextSearchPage extends StatefulWidget {
  const ReadingTextSearchPage({super.key, required this.source, this.search});
  final Future<List<ReadingSearchResult>> Function(String)? search;
  final ReadingTextSource source;
  @override
  State<ReadingTextSearchPage> createState() => _ReadingTextSearchPageState();
}

class _ReadingTextSearchPageState extends State<ReadingTextSearchPage> {
  final _query = TextEditingController();
  List<ReadingSearchResult> _results = [];
  int _generation = 0;
  bool _busy = false, _searched = false;
  String? _error;
  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.length < 2 || query.length > 200) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _searched = true;
    });
    try {
      final results = await (widget.search ?? widget.source.search)(query);
      if (mounted && generation == _generation) {
        setState(() => _results = results);
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = 'Search failed. Try again.');
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Search publication')),
    body: SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _query,
                maxLength: 200,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  labelText: 'Search text',
                  suffixIcon: IconButton(
                    tooltip: 'Search',
                    icon: const AppIcon(AppIconRole.search),
                    onPressed: _search,
                  ),
                ),
              ),
            ),
          ),
          if (_busy) const SliverToBoxAdapter(child: LinearProgressIndicator()),
          if (_error != null || _searched && !_busy && _results.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: AppSpacing.of(context).all(16),
                child: Text(_error ?? 'No matches. Try another search.'),
              ),
            )
          else
            SliverList.builder(
              itemCount: _results.length,
              itemBuilder: (context, i) {
                final result = _results[i];
                return ListTile(
                  title: Text(result.context),
                  onTap: () => Navigator.pop(context, result),
                );
              },
            ),
          if (_results.length == 200)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'Showing the first 200 matches. Refine your search.',
                ),
              ),
            ),
        ],
      ),
    ),
  );
  @override
  void dispose() {
    _generation++;
    unawaited(widget.source.cancel().catchError((Object _) {}));
    _query.dispose();
    super.dispose();
  }
}

class _PublicationIllustration extends StatefulWidget {
  const _PublicationIllustration({
    super.key,
    required this.source,
    required this.resource,
    required this.href,
    required this.label,
  });
  final ReadingImages source;
  final String resource, href, label;
  @override
  State<_PublicationIllustration> createState() =>
      _PublicationIllustrationState();
}

class _PublicationIllustrationState extends State<_PublicationIllustration> {
  late Future<Uint8List> image = widget.source.image(
    widget.resource,
    widget.href,
  );
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: FutureBuilder<Uint8List>(
      future: image,
      builder: (_, snapshot) {
        if (snapshot.hasError) {
          return TextButton.icon(
            onPressed: () => setState(
              () => image = widget.source.image(widget.resource, widget.href),
            ),
            icon: const AppIcon(AppIconRole.refresh),
            label: Text(
              widget.label.isEmpty ? 'Retry illustration' : widget.label,
            ),
          );
        }
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return Image.memory(
          snapshot.data!,
          cacheWidth: 1200,
          fit: BoxFit.contain,
          semanticLabel: widget.label,
          gaplessPlayback: true,
        );
      },
    ),
  );
}
