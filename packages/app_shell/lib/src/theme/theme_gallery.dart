import 'package:flutter/material.dart';

import '../pixel_theme.dart';

/// Interactive preview of app-owned components; content artwork stays untouched.
class ThemeGallery extends StatefulWidget {
  const ThemeGallery({super.key, required this.data});
  final ThemeData data;
  @override
  State<ThemeGallery> createState() => _ThemeGalleryState();
}

class _ThemeGalleryState extends State<ThemeGallery> {
  bool selected = true;
  double progress = .4;
  @override
  Widget build(BuildContext context) => Theme(
    data: widget.data,
    child: Builder(
      builder: (context) => Material(
        color: widget.data.scaffoldBackgroundColor,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Component preview',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const AppGap(12),
              const Wrap(
                spacing: 12,
                children: [
                  AppIcon(AppIconRole.back),
                  AppIcon(AppIconRole.settings),
                  AppIcon(AppIconRole.play),
                  AppIcon(AppIconRole.artwork),
                ],
              ),
              const AppGap(12),
              Card(
                child: ListTile(
                  title: const Text('Title'),
                  subtitle: const Text('Metadata'),
                  trailing: const AppIcon(AppIconRole.menu),
                  onTap: () {},
                ),
              ),
              const AppGap(12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(onPressed: () {}, child: const Text('Play')),
                  const FilledButton(onPressed: null, child: Text('Disabled')),
                  OutlinedButton(
                    onPressed: () {},
                    child: const Text('Details'),
                  ),
                  TextButton(onPressed: () {}, child: const Text('Edit')),
                ],
              ),
              const AppGap(12),
              const TextField(
                decoration: InputDecoration(
                  labelText: 'Search',
                  prefixIcon: AppIcon(AppIconRole.search),
                ),
              ),
              const AppGap(12),
              const TextField(
                enabled: false,
                decoration: InputDecoration(labelText: 'Disabled field'),
              ),
              const AppGap(12),
              const TextField(
                decoration: InputDecoration(
                  labelText: 'Validation',
                  errorText: 'Example error',
                ),
              ),
              InterfaceSwitchListTile(
                value: selected,
                onChanged: (v) => setState(() => selected = v),
                title: const Text('Option'),
              ),
              CheckboxListTile(
                value: selected,
                onChanged: (v) => setState(() => selected = v!),
                title: const Text('Selection'),
              ),
              RadioGroup<int>(
                groupValue: selected ? 0 : 1,
                onChanged: (value) => setState(() => selected = value == 0),
                child: const Column(
                  children: [
                    RadioListTile<int>(value: 0, title: Text('First option')),
                    RadioListTile<int>(value: 1, title: Text('Second option')),
                  ],
                ),
              ),
              const DefaultTabController(
                length: 2,
                child: TabBar(
                  tabs: [
                    Tab(text: 'Home'),
                    Tab(text: 'Search'),
                  ],
                ),
              ),
              Slider(
                value: progress,
                onChanged: (v) => setState(() => progress = v),
              ),
              LinearProgressIndicator(value: progress),
              const AppGap(12),
              Wrap(
                spacing: 8,
                children: [
                  const Chip(label: Text('Tag')),
                  FilterChip(
                    label: const Text('Filter'),
                    selected: selected,
                    onSelected: (v) => setState(() => selected = v),
                  ),
                ],
              ),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('Grid')),
                  ButtonSegment(value: 1, label: Text('List')),
                ],
                selected: {selected ? 0 : 1},
                onSelectionChanged: (v) =>
                    setState(() => selected = v.first == 0),
              ),
              const AppGap(12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: () {},
                    icon: const AppIcon(AppIconRole.previous),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: const AppIcon(AppIconRole.play),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: const AppIcon(AppIconRole.next),
                  ),
                ],
              ),
              TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Dialog'),
                    content: const Text('Body text'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
                child: const Text('Preview dialog'),
              ),
              PopupMenuButton<String>(
                tooltip: 'Preview menu',
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'settings', child: Text('Settings')),
                  PopupMenuItem(enabled: false, child: Text('Unavailable')),
                ],
              ),
              NavigationBar(
                selectedIndex: selected ? 0 : 1,
                onDestinationSelected: (v) => setState(() => selected = v == 0),
                destinations: const [
                  NavigationDestination(
                    icon: AppIcon(AppIconRole.library),
                    label: 'Library',
                  ),
                  NavigationDestination(
                    icon: AppIcon(AppIconRole.spaces),
                    label: 'Spaces',
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
