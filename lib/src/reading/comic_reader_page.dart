import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../experience/navigation/navigation_coordinator.dart';
import 'reader_host.dart';

import 'package:app_shell/app_shell.dart';

import 'comic_reader_controller.dart';
import 'comic_reader_layout.dart';
import 'comic_reader_settings.dart';
import '../features/reading/application/reader_keys.dart';
import 'domain/reader_adapter.dart';
import 'domain/reading_catalog.dart';
import '../features/catalog/application/reading_catalog_commands.dart';
import 'reading_comic_notes.dart';
import 'domain/reading_location.dart';
import '../features/reading/application/reading_session.dart';
import 'text_reader_layout.dart' show ReaderPalette;

/// Opens the fixed-page adapter through the shared navigation/session owners.
Future<void> openComicReader(
  BuildContext context,
  ReaderHost service,
  ReadingTitle title, {
  required bool Function(String) authorized,
  PageReadingLocation? initialLocation,
  Future<void> Function(BuildContext)? chooseReader,
}) => NavigationCoordinator.forOwner(service.persistenceOwner).run(
  'reader:${title.catalog.id.collectionId}:${title.catalog.id.entityId}',
  () async {
    if (!context.mounted || !authorized(title.catalog.id.collectionId)) return;
    final reader = service.pages(title.format);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ComicReaderPage(
          title: title,
          controller: reader.controller,
          workflows: reader.workflows,
          volumeKeys: reader.keys,
          chooseReader: chooseReader,
          initialLocation: initialLocation,
          session: reader.session,
        ),
      ),
    );
  },
);

class ComicReaderPage extends StatefulWidget {
  const ComicReaderPage({
    super.key,
    required this.title,
    required this.controller,
    required this.session,
    this.volumeKeys,
    this.workflows,
    this.chooseReader,
    this.initialLocation,
  });
  final ReadingTitle title;
  final ComicReaderController controller;
  final ReadingSession session;
  final ComicVolumeKeys? volumeKeys;
  final ReadingCatalogCommands? workflows;
  final Future<void> Function(BuildContext)? chooseReader;
  final PageReadingLocation? initialLocation;
  @override
  State<ComicReaderPage> createState() => _ComicReaderPageState();
}

class _ComicReaderPageState extends State<ComicReaderPage>
    with WidgetsBindingObserver {
  ComicReaderController get c => widget.controller;
  final _transform = TransformationController();
  late final ComicVolumeKeys _keys = widget.volumeKeys ?? const NoReaderKeys();
  ComicReaderLayout? _layout;
  String _geometry = '';
  bool _opening = true,
      _ready = false,
      _chrome = true,
      _closing = false,
      _allowPop = false,
      _turning = false,
      _settingsOpen = false;
  bool _active = true, _programmatic = false, _chromeUpdateScheduled = false;
  Object? _openError;
  String? _saveError;
  Timer? _timer;
  Future<void> _saving = Future.value();
  Offset? _pointerStart;
  int _pointers = 0, _maxPointers = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.addListener(_changed);
    _transform.addListener(_transformed);
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
      setState(() {
        _ready = true;
        _opening = false;
        _geometry = '';
      });
      await _configureKeys();
      unawaited(c.prefetch(c.pageIndex + 1));
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
    if (_ready && !_closing && !c.loading && c.pages.isNotEmpty) {
      _scheduleSave();
    }
  }

  void _scheduleSave() {
    _timer?.cancel();
    _timer = Timer(
      const Duration(milliseconds: 700),
      () => unawaited(_persist()),
    );
  }

  Future<bool> _persist() async {
    if (!_ready || widget.session.state != ReaderSessionState.open) return true;
    var success = false;
    _saving = _saving.then((_) async {
      try {
        await widget.session.save();
        success = true;
        if (mounted && _saveError != null) setState(() => _saveError = null);
      } catch (_) {
        if (mounted) {
          setState(
            () =>
                _saveError = 'Could not save your page. Retry before leaving.',
          );
        }
      }
    });
    await _saving;
    return success;
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not complete this action. Check the source or try again.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _configureKeys() {
    if (!mounted) return _keys.close();
    return _keys.configure(
      _ready &&
          !_closing &&
          !_settingsOpen &&
          _active &&
          c.preferences['volumeKeys'] == true,
      (forward) {
        if (!_turning && !_settingsOpen && mounted) {
          unawaited(_run(() => _turn(forward)));
        }
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (_active) {
      _geometry = '';
      if (mounted) setState(() {});
    }
    unawaited(_configureKeys().catchError((Object _) {}));
    if (!_active) {
      _timer?.cancel();
      unawaited(_persist());
    }
  }

  Future<void> _leave({bool discard = false}) async {
    if (_closing) return;
    setState(() => _closing = true);
    _timer?.cancel();
    await _configureKeys();
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
          _saveError = 'Could not save your page. Retry before leaving.';
        });
      }
      await _configureKeys();
    }
  }

  Future<void> _jump(int index, {double withinPage = 0}) async {
    if (_turning || c.loading) return;
    _turning = true;
    try {
      if (!await _persist()) return;
      await c.jump(index, withinPage: withinPage);
      _geometry = '';
      if (mounted) setState(() {});
      unawaited(c.prefetch(index + 1));
    } finally {
      _turning = false;
    }
  }

  Future<void> _turn(bool forward) async {
    if (_layout == null || _turning || !_ready || _closing) return;
    if (c.webtoon) {
      final origin = _transform.toScene(Offset.zero);
      final scale = _transform.value.getMaxScaleOnAxis();
      final maxY = math.max(
        0.0,
        _layout!.size.height - _layout!.viewport.height / scale,
      );
      final y =
          (origin.dy +
                  (forward ? 1 : -1) * _layout!.viewport.height * .85 / scale)
              .clamp(0.0, maxY);
      _setOrigin(Offset(origin.dx, y.toDouble()), scale);
      _capture();
      return;
    }
    final origin = _transform.toScene(Offset.zero);
    final scale = _transform.value.getMaxScaleOnAxis();
    final maxY = math.max(
      0.0,
      _layout!.size.height - _layout!.viewport.height / scale,
    );
    if (forward && origin.dy + 1 < maxY || !forward && origin.dy > 1) {
      final y =
          (origin.dy +
                  (forward ? 1 : -1) * _layout!.viewport.height * .85 / scale)
              .clamp(0.0, maxY);
      _setOrigin(Offset(origin.dx, y.toDouble()), scale);
      _capture();
      return;
    }
    await _jump(
      c.turnTarget(
        forward,
        landscape: _layout!.viewport.width > _layout!.viewport.height,
      ),
    );
  }

  void _setOrigin(Offset origin, double scale) {
    final layout = _layout;
    final x = layout == null
        ? origin.dx
        : origin.dx.clamp(
            0.0,
            math.max(0.0, layout.size.width - layout.viewport.width / scale),
          );
    final y = layout == null
        ? origin.dy
        : origin.dy.clamp(
            0.0,
            math.max(0.0, layout.size.height - layout.viewport.height / scale),
          );
    _programmatic = true;
    try {
      _transform.value = Matrix4.identity()
        ..setEntry(0, 0, scale)
        ..setEntry(1, 1, scale)
        ..setTranslationRaw(-x * scale, -y * scale, 0);
    } finally {
      _programmatic = false;
    }
  }

  void _transformed() {
    if (_programmatic ||
        !_ready ||
        !_active ||
        _closing ||
        _layout == null ||
        c.pages.isEmpty ||
        !c.authorized(widget.title.catalog.id.collectionId)) {
      return;
    }
    final (index, fraction) = _layout!.anchor(_transform.toScene(Offset.zero));
    c.anchor(index, fraction);
    _scheduleSave();
    if (!_chromeUpdateScheduled && mounted) {
      _chromeUpdateScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _chromeUpdateScheduled = false;
        if (mounted) setState(() {});
      });
    }
  }

  void _capture() {
    if (_layout == null ||
        !_ready ||
        c.pages.isEmpty ||
        _closing ||
        !c.authorized(widget.title.catalog.id.collectionId)) {
      return;
    }
    final (index, fraction) = _layout!.anchor(_transform.toScene(Offset.zero));
    c.anchor(index, fraction);
    _scheduleSave();
    // Update only chrome; the scene geometry stays stable while dragging.
    if (mounted) setState(() {});
  }

  void _tap(TapUpDetails details) {
    if (_layout == null) return;
    final x = details.localPosition.dx / _layout!.viewport.width;
    if (c.preferences['tapZones'] == 'off' || x >= .3 && x <= .7) {
      setState(() => _chrome = !_chrome);
      return;
    }
    var forward = c.rtl ? x < .3 : x > .7;
    if (c.preferences['tapZones'] == 'inverted') forward = !forward;
    unawaited(_run(() => _turn(forward)));
  }

  Future<void> _settings() async {
    _settingsOpen = true;
    await _configureKeys();
    try {
      if (!mounted) return;
      await showComicReaderSettings(context, c);
    } finally {
      _settingsOpen = false;
      _geometry = '';
      await _configureKeys();
      if (mounted) setState(() {});
    }
  }

  Future<void> _contents() async {
    _settingsOpen = true;
    await _configureKeys();
    try {
      if (!mounted) return;
      final selected = await showDialog<int>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Pages'),
          children: [
            SizedBox(
              width: 400,
              height: MediaQuery.sizeOf(context).height * .6,
              child: ListView.builder(
                itemCount: c.pages.length,
                itemBuilder: (_, i) => ListTile(
                  selected: i == c.pageIndex,
                  leading: c.pdf
                      ? SizedBox(
                          width: 48,
                          height: 64,
                          child: FutureBuilder<Uint8List>(
                            future: c.tile(i, c.pages[i].bounds, 96),
                            builder: (_, snapshot) => snapshot.hasData
                                ? Image.memory(
                                    snapshot.data!,
                                    fit: BoxFit.contain,
                                  )
                                : const AppIcon(AppIconRole.reading),
                          ),
                        )
                      : null,
                  title: Text('Page ${i + 1}'),
                  subtitle: Text(c.title.readingOrder[i].label),
                  onTap: () => Navigator.pop(context, i),
                ),
              ),
            ),
          ],
        ),
      );
      if (selected != null) await _jump(selected);
    } finally {
      _settingsOpen = false;
      await _configureKeys();
    }
  }

  void _menuOpen(bool value) {
    _settingsOpen = value;
    unawaited(_configureKeys().catchError((Object _) {}));
  }

  Future<void> _menuSelected(String value) async {
    try {
      await _run(switch (value) {
        'pages' => _contents,
        'bookmark' => () async {
          final location = await c.location();
          if (!mounted) return;
          await addComicNote(
            context,
            widget.workflows!,
            c.title,
            location,
            bookmark: true,
          );
        },
        'note' => () async {
          final location = await c.location();
          if (!mounted) return;
          await addComicNote(
            context,
            widget.workflows!,
            c.title,
            location,
            bookmark: false,
          );
        },
        'notes' => () async {
          final page = await showComicNotes(
            context,
            widget.workflows!,
            c.title,
          );
          if (page != null) {
            await _jump(page.pageIndex, withinPage: page.offset);
          }
        },
        'settings' => _settings,
        'zoom' => () async {
          _geometry = '';
          setState(() {});
        },
        _ => () => _finished(!widget.session.finished),
      });
    } finally {
      _menuOpen(false);
    }
  }

  Future<void> _finished(bool value) async {
    final old = widget.session.finished;
    final operation = _saving.then((_) => widget.session.save(finished: value));
    _saving = operation.catchError((Object _) {});
    await operation;
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(value ? 'Marked finished' : 'Marked unread'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => _run(() => _finished(old)),
        ),
      ),
    );
  }

  Widget _scene() => LayoutBuilder(
    builder: (context, constraints) {
      final viewport = constraints.biggest;
      if (viewport.width <= 0 || viewport.height <= 0) return const SizedBox();
      // Chrome visibility must not change the canonical page/within-page anchor.
      final pagedIndex = c.webtoon ? '' : '${c.pageIndex}';
      final signature = '$viewport:$pagedIndex:${c.preferences}';
      if (_geometry != signature || _layout == null) {
        _layout = ComicReaderLayout(c, viewport);
        _geometry = signature;
        _setOrigin(_layout!.originFor(c.pageIndex, c.offset), 1);
      }
      return Listener(
        onPointerDown: (e) {
          if (_pointers++ == 0) {
            _pointerStart = e.position;
            _maxPointers = 1;
          }
          _maxPointers = math.max(_maxPointers, _pointers);
        },
        onPointerUp: (e) {
          _pointers = math.max(0, _pointers - 1);
          if (_pointers == 0 &&
              _maxPointers == 1 &&
              _pointerStart != null &&
              !c.webtoon &&
              _transform.value.getMaxScaleOnAxis() < 1.01) {
            final delta = e.position - _pointerStart!;
            if (delta.dx.abs() > 70 && delta.dx.abs() > delta.dy.abs() * 1.5) {
              unawaited(_run(() => _turn(c.rtl ? delta.dx > 0 : delta.dx < 0)));
            }
          }
        },
        onPointerCancel: (_) {
          _pointers = 0;
          _pointerStart = null;
        },
        onPointerSignal: (e) {
          if (e is PointerScrollEvent) {
            GestureBinding.instance.pointerSignalResolver.register(e, (event) {
              final origin = _transform.toScene(Offset.zero),
                  scale = _transform.value.getMaxScaleOnAxis();
              final y = (origin.dy + e.scrollDelta.dy / scale).clamp(
                0.0,
                math.max(0.0, _layout!.size.height - viewport.height / scale),
              );
              _setOrigin(Offset(origin.dx, y.toDouble()), scale);
              _capture();
            });
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: _tap,
          onDoubleTap: () {
            final zoom = _transform.value.getMaxScaleOnAxis();
            final center = _layout!.viewport.center(Offset.zero);
            final sceneCenter = _transform.toScene(center);
            final scale = zoom > 1.01 ? 1.0 : 2.0;
            _setOrigin(sceneCenter - center / scale, scale);
            _capture();
          },
          child: InteractiveViewer.builder(
            transformationController: _transform,
            minScale: 1,
            maxScale: 4,
            alignment: Alignment.topLeft,
            onInteractionUpdate: (_) => _capture(),
            onInteractionEnd: (_) => _capture(),
            builder: (context, quad) {
              final visible = Rect.fromLTRB(
                quad.point0.x,
                quad.point0.y,
                quad.point2.x,
                quad.point2.y,
              );
              final tiles = _layout!.tiles(
                visible,
                MediaQuery.devicePixelRatioOf(context),
                _transform.value.getMaxScaleOnAxis(),
              );
              return SizedBox(
                width: _layout!.size.width,
                height: _layout!.size.height,
                child: Stack(
                  children: [
                    for (final tile in tiles)
                      Positioned.fromRect(
                        rect: tile.destination,
                        child: _ComicTile(
                          key: ValueKey(
                            '${c.title.sourceRevision}:${tile.key}',
                          ),
                          controller: c,
                          tile: tile,
                        ),
                      ),
                    if (_layout!.truncated)
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Material(
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text('Zoom in to view more pages'),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    },
  );
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
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent || !_ready || _settingsOpen) {
            return KeyEventResult.ignored;
          }
          final key = event.logicalKey;
          final forward =
              key == LogicalKeyboardKey.pageDown ||
              key == LogicalKeyboardKey.arrowRight && !c.rtl ||
              key == LogicalKeyboardKey.arrowLeft && c.rtl;
          final backward =
              key == LogicalKeyboardKey.pageUp ||
              key == LogicalKeyboardKey.arrowLeft && !c.rtl ||
              key == LogicalKeyboardKey.arrowRight && c.rtl;
          if (!forward && !backward) return KeyEventResult.ignored;
          unawaited(_run(() => _turn(forward)));
          return KeyEventResult.handled;
        },
        child: Scaffold(
          backgroundColor: palette.background,
          appBar: _chrome || !_ready
              ? AppBar(
                  title: Text(widget.title.catalog.title),
                  leading: IconButton(
                    tooltip: 'Back',
                    onPressed: _closing ? null : () => _leave(),
                    icon: const AppIcon(AppIconRole.back),
                  ),
                  actions: [
                    if (_ready)
                      PopupMenuButton<String>(
                        icon: const AppIcon(AppIconRole.menu),
                        tooltip: 'Reader actions',
                        onOpened: () => _menuOpen(true),
                        onCanceled: () => _menuOpen(false),
                        onSelected: _menuSelected,
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'pages',
                            child: Text('Pages'),
                          ),
                          PopupMenuItem(
                            value: 'settings',
                            child: Text(
                              c.pdf
                                  ? 'PDF appearance'
                                  : 'Comic reader settings',
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'zoom',
                            child: Text('Reset zoom'),
                          ),
                          if (widget.workflows != null) ...[
                            const PopupMenuItem(
                              value: 'bookmark',
                              child: Text('Bookmark page'),
                            ),
                            const PopupMenuItem(
                              value: 'note',
                              child: Text('Add page note'),
                            ),
                            const PopupMenuItem(
                              value: 'notes',
                              child: Text('Saved pages and notes'),
                            ),
                          ],
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
                )
              : null,
          body: SafeArea(
            child: Column(
              children: [
                if (_saveError != null)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * .3,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          Text(_saveError!),
                          Wrap(
                            children: [
                              TextButton(
                                onPressed: () => _persist(),
                                child: const Text('Retry save'),
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
                Expanded(
                  child: _opening || _ready && c.pages.isEmpty
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
                                          _openError is ComicLocationRecovery
                                      ? 'The saved page needs recovery. Your saved progress is retained.'
                                      : (_openError is PlatformException
                                            ? (_openError as PlatformException)
                                                      .message ??
                                                  'Could not open this publication.'
                                            : 'Could not open this publication. Check its source and folder access.'),
                                ),
                                TextButton(
                                  onPressed: () => _open(),
                                  child: const Text('Retry'),
                                ),
                                if (c.pdf && widget.chooseReader != null)
                                  TextButton.icon(
                                    icon: const AppIcon(
                                      AppIconRole.externalLink,
                                    ),
                                    label: const Text('Open with…'),
                                    onPressed: () => _run(
                                      () => widget.chooseReader!(context),
                                    ),
                                  ),
                                if (_openError is ReadingRecoveryRequired ||
                                    _openError is ComicLocationRecovery)
                                  TextButton(
                                    onPressed: () => _open(restart: true),
                                    child: const Text('Start again'),
                                  ),
                              ],
                            ),
                          ),
                        )
                      : Semantics(
                          label:
                              '${c.pdf ? 'PDF' : 'Comic'} page ${c.pageIndex + 1} of ${c.pages.length}',
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _scene(),
                              if (c.loading)
                                const Center(
                                  child: CircularProgressIndicator(),
                                ),
                            ],
                          ),
                        ),
                ),
                if (_ready && _chrome)
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Pages',
                        onPressed: () => _run(_contents),
                        icon: const AppIcon(AppIconRole.reading),
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
                          'Page ${c.pageIndex + 1} of ${c.pages.length}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next page',
                        onPressed: c.loading
                            ? null
                            : () => _run(() => _turn(true)),
                        icon: const AppIcon(AppIconRole.forward),
                      ),
                      IconButton(
                        tooltip: c.pdf
                            ? 'PDF appearance'
                            : 'Comic reader settings',
                        onPressed: () => _run(_settings),
                        icon: const AppIcon(AppIconRole.settings),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    c.removeListener(_changed);
    unawaited(_keys.close().catchError((Object _) {}));
    unawaited(
      _saving.then((_) => widget.session.discard()).catchError((Object _) {}),
    );
    _transform.removeListener(_transformed);
    _transform.dispose();
    c.dispose();
    super.dispose();
  }
}

/// Owns decoded pixels explicitly instead of retaining tiles in Flutter's global ImageCache.
class _ComicTile extends StatefulWidget {
  const _ComicTile({super.key, required this.controller, required this.tile});
  final ComicReaderController controller;
  final ComicTilePlacement tile;
  @override
  State<_ComicTile> createState() => _ComicTileState();
}

class _ComicTileState extends State<_ComicTile> {
  ui.Image? _image;
  bool _failed = false;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final request = ++_request;
    if (mounted) setState(() => _failed = false);
    try {
      final t = widget.tile;
      final bytes = await widget.controller.tile(
        t.page,
        t.source,
        t.targetWidth,
      );
      if (!mounted || request != _request) return;
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        if (!mounted || request != _request) {
          frame.image.dispose();
          return;
        }
        if (frame.image.width * frame.image.height > 524288) {
          frame.image.dispose();
          throw const FormatException('Comic tile exceeds capacity');
        }
        setState(() {
          _image?.dispose();
          _image = frame.image;
        });
      } finally {
        codec.dispose();
      }
    } catch (_) {
      if (mounted && request == _request) {
        final t = widget.tile;
        widget.controller.evictTile(t.page, t.source, t.targetWidth);
        setState(() => _failed = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) => _failed
      ? Center(
          child: IconButton(
            tooltip: 'Retry page image',
            icon: const AppIcon(AppIconRole.refresh),
            onPressed: _load,
          ),
        )
      : _image == null
      ? const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(),
          ),
        )
      : RawImage(
          image: _image,
          fit: BoxFit.fill,
          filterQuality: FilterQuality.medium,
        );
  @override
  void dispose() {
    _request++;
    _image?.dispose();
    super.dispose();
  }
}
