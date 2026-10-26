import 'package:flutter/material.dart';

import 'package:app_shell/app_shell.dart';

import 'library_models.dart';
import 'library_controller.dart';
import 'series.dart';

class SeriesGroupingPage extends StatefulWidget {
  const SeriesGroupingPage({
    super.key,
    required this.library,
    required this.collectionId,
    this.initial,
  });
  final LibraryController library;
  final String collectionId;
  final String? initial;
  @override
  State<SeriesGroupingPage> createState() => _SeriesGroupingPageState();
}

class _SeriesGroupingPageState extends State<SeriesGroupingPage> {
  final name = TextEditingController(),
      season = TextEditingController(text: '1'),
      episode = TextEditingController(text: '1');
  late final selected = <String>{if (widget.initial != null) widget.initial!};
  bool busy = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    season.dispose();
    episode.dispose();
    super.dispose();
  }

  Future<void> save(bool ungroup) async {
    final seasonNumber = int.tryParse(season.text),
        first = int.tryParse(episode.text);
    if (selected.isEmpty ||
        (!ungroup &&
            (name.text.trim().isEmpty ||
                seasonNumber == null ||
                seasonNumber < 0 ||
                first == null ||
                first < 1))) {
      setState(
        () => error = 'Select episodes, enter a series name and valid season/episode numbers.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final assets = widget.library
          .items(widget.collectionId)
          .where((a) => selected.contains(a.id))
          .toList();
      final edits = <VideoAsset>[];
      for (var i = 0; i < assets.length; i++) {
        final a = assets[i];
        edits.add(
          VideoAsset.fromJson({
            ...a.toJson(),
            'metadata': {
              ...a.metadata,
              'groupId': ungroup
                  ? 'ungrouped:${a.id}'
                  : name.text.trim().toLowerCase(),
              'series': ungroup ? a.title : name.text.trim(),
              'season': ungroup ? '1' : '$seasonNumber',
              'episode': ungroup ? '1' : '${first! + i}',
              'groupOrder': '',
            },
            'metadataSource': 'manual',
          }, VideoSubtype.tv),
        );
      }
      await widget.library.correctGrouping(edits);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'Could not finish grouping. Your previous grouping was kept.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final assets = widget.library
        .items(widget.collectionId)
        .where((a) => a.mediaSubtype == VideoSubtype.tv)
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Series grouping')),
      body: ListView(
        padding: AppSpacing.of(context).all(20),
        children: [
          TextField(
            controller: name,
            decoration: const InputDecoration(
              labelText: 'Series name (existing name merges groups)',
            ),
          ),
          const AppGap(16),
          TextField(
            controller: season,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Season (0 for specials)',
            ),
          ),
          const AppGap(16),
          TextField(
            controller: episode,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Starting episode number',
            ),
          ),
          const AppGap(12),
          const Text(
            'Selected episodes receive consecutive episode numbers in the order shown. Files and playback history stay linked to their existing identities.',
          ),
          for (final asset in assets)
            CheckboxListTile(
              value: selected.contains(asset.id),
              onChanged: busy
                  ? null
                  : (checked) => setState(() {
                      if (checked == true) {
                        selected.add(asset.id);
                      } else {
                        selected.remove(asset.id);
                      }
                    }),
              title: Text(asset.title),
              subtitle: Text(
                '${asset.metadata['series'] ?? ''} · S${seasonNumber(asset) ?? '?'} E${episodeNumber(asset) ?? '?'}',
              ),
            ),
          if (error != null) Text(error!),
          FilledButton.icon(
            onPressed: busy ? null : () => save(false),
            icon: const AppIcon(AppIconRole.confirm),
            label: Text(busy ? 'Saving…' : 'Apply grouping'),
          ),
          TextButton(
            onPressed: busy ? null : () => save(true),
            child: const Text('Ungroup selected episodes'),
          ),
        ],
      ),
    );
  }
}
