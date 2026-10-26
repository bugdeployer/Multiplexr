import 'package:flutter/material.dart';

import 'package:app_shell/app_shell.dart';

import 'contracts.dart';
import 'music_catalog_models.dart';

class MusicTrackPicker extends StatefulWidget {
  const MusicTrackPicker({super.key, required this.options});
  final List<MusicTrack> options;
  @override
  State<MusicTrackPicker> createState() => _MusicTrackPickerState();
}

class _MusicTrackPickerState extends State<MusicTrackPicker> {
  final query = TextEditingController();
  final selected = <MediaId>{};
  String album = '';
  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.options
        .where(
          (t) =>
              (album.isEmpty || t.metadata.album == album) &&
              '${t.metadata.title} ${t.metadata.artist} ${t.metadata.album}'
                  .toLowerCase()
                  .contains(query.text.toLowerCase()),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select tracks'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              widget.options.where((t) => selected.contains(t.id)).toList(),
            ),
            child: Text('Add (${selected.length})'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: AppSpacing.of(context).all(20),
            child: Column(
              children: [
                TextField(
                  controller: query,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Search tracks, artists or albums',
                    prefixIcon: const AppIcon(AppIconRole.search),
                    suffixIcon: IconButton(
                      tooltip: 'Clear search',
                      icon: const AppIcon(AppIconRole.close),
                      onPressed: () => setState(query.clear),
                    ),
                  ),
                ),
                const AppGap(16),
                DropdownButtonFormField<String>(
                  icon: const AppIcon(AppIconRole.expand),
                  initialValue: album,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Album'),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('All albums'),
                    ),
                    for (final value
                        in widget.options
                            .map((t) => t.metadata.album)
                            .where((s) => s.isNotEmpty)
                            .toSet())
                      DropdownMenuItem(
                        value: value,
                        child: Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => album = v!),
                ),
                Wrap(
                  spacing: 12,
                  children: [
                    TextButton(
                      onPressed: () => setState(
                        () => selected.addAll(options.map((t) => t.id)),
                      ),
                      child: const Text('Select all visible'),
                    ),
                    TextButton(
                      onPressed: () => setState(selected.clear),
                      child: const Text('Clear selection'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: options.isEmpty
                ? const Center(
                    child: Text(
                      'No matching tracks. Clear search or change the album.',
                    ),
                  )
                : ListView.builder(
                    itemCount: options.length,
                    itemBuilder: (_, i) {
                      final track = options[i];
                      return CheckboxListTile(
                        value: selected.contains(track.id),
                        title: Text(track.metadata.title),
                        subtitle: Text(
                          '${track.metadata.artist} · ${track.metadata.album}',
                        ),
                        onChanged: (v) => setState(
                          () => v == true
                              ? selected.add(track.id)
                              : selected.remove(track.id),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
