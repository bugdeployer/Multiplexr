import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'settings.dart';
import 'theme_picker.dart';
import 'pixel_theme.dart';

enum ShellSettingsSection { appearance, security, notifications }

class ShellNotificationCategory {
  const ShellNotificationCategory(this.id, this.label, this.description);
  final String id, label, description;
}

const defaultShellNotificationCategories = [
  ShellNotificationCategory('completed', 'Completed', 'When work completes.'),
  ShellNotificationCategory(
    'errors',
    'Errors',
    'Problems that need attention.',
  ),
  ShellNotificationCategory(
    'activity',
    'Activity',
    'Progress from background work.',
  ),
];

class ShellSettingsPanel extends StatefulWidget {
  const ShellSettingsPanel({
    super.key,
    required this.settings,
    required this.section,
    this.categories = defaultShellNotificationCategories,
  });
  final ShellSettingsController settings;
  final ShellSettingsSection section;
  final List<ShellNotificationCategory> categories;
  @override
  State<ShellSettingsPanel> createState() => _ShellSettingsPanelState();
}

class _ShellSettingsPanelState extends State<ShellSettingsPanel> {
  ShellSettingsController get s => widget.settings;
  String? selectedTestCategory;
  String get testCategory =>
      widget.categories.any((c) => c.id == selectedTestCategory)
      ? selectedTestCategory!
      : widget.categories.first.id;
  bool busy = false;
  Future<void> changeSecurity({
    int? delay,
    bool? biometrics,
    bool? previews,
    bool? screen,
  }) => run(() async {
    if (!await s.security(
          delay: delay,
          biometrics: biometrics,
          previews: previews,
          screen: screen,
        ) &&
        mounted) {
      message(
        'Security settings were not changed. Authentication is required.',
      );
    }
  });

  void message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
    });
    try {
      await action();
    } on PlatformException catch (e) {
      if (mounted) {
        message(e.message ?? 'The device could not complete this action.');
      }
    } catch (_) {
      if (mounted) message('Could not save this change. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: s,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: validatedContent(context),
    ),
  );
  List<Widget> validatedContent(BuildContext context) {
    final ids = widget.categories.map((c) => c.id).toList();
    if (ids.isEmpty ||
        ids.toSet().length != ids.length ||
        ids.any((id) => !s.categories.containsKey(id))) {
      throw ArgumentError(
        'Panel categories must be unique IDs configured on the settings controller.',
      );
    }
    return content(context);
  }

  List<Widget> content(BuildContext context) {
    if (widget.section == ShellSettingsSection.appearance) {
      return [
        panel([ThemePicker(settings: s)]),
        const AppGap(20),
        panel([
          InterfaceSwitchListTile(
            title: const Text('Follow system'),
            subtitle: const Text('Switch Light and Dark with your device.'),
            value: s.followSystem,
            onChanged: busy ? null : (v) => run(() => s.preferences(system: v)),
          ),
        ]),
        const AppGap(20),
        panel([
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 8, 8, 16),
            child: Text(
              'Color mode',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ),
          SegmentedButton<bool>(
            selectedIcon: const AppIcon(AppIconRole.confirm),
            segments: const [
              ButtonSegment(
                value: false,
                icon: AppIcon(AppIconRole.lightMode),
                label: Text('Light'),
              ),
              ButtonSegment(
                value: true,
                icon: AppIcon(AppIconRole.darkMode),
                label: Text('Dark'),
              ),
            ],
            selected: {s.dark},
            onSelectionChanged: busy
                ? null
                : (v) => run(() => s.appearance(isDark: v.first)),
          ),
        ]),
        const AppGap(24),
        heading('BASE COLOR'),
        swatches(
          s.bases,
          s.baseIndex,
          (i) => run(() => s.appearance(baseChoice: i)),
          'base',
        ),
        const AppGap(20),
        heading('ACCENT COLOR'),
        swatches(
          s.accents,
          s.accentIndex,
          (i) => run(() => s.appearance(accentChoice: i)),
          'accent',
        ),
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(
            'Colors are saved separately for light and dark mode.',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),

        const AppGap(28),
        heading('LAYOUT & MOTION'),
        panel([
          InterfaceSwitchListTile(
            title: const Text('Compact layout'),
            subtitle: const Text('Tighter page spacing and denser controls.'),
            value: s.compact,
            onChanged: busy ? null : (v) => run(() => s.preferences(dense: v)),
          ),
          InterfaceSwitchListTile(
            title: const Text('Reduce motion'),
            subtitle: const Text(
              'Minimize transitions. Your device motion setting is also respected.',
            ),
            value: s.reduceMotion,
            onChanged: busy ? null : (v) => run(() => s.preferences(motion: v)),
          ),
        ]),
      ];
    }
    if (widget.section == ShellSettingsSection.security) {
      return [
        panel([
          InterfaceSwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            title: const Text('App lock'),
            subtitle: const Text(
              'Always lock on launch. Returning to the app follows your lock delay.',
            ),
            value: s.lockEnabled,
            onChanged:
                busy || !s.supported || (!s.secureDevice && !s.lockEnabled)
                ? null
                : (v) => run(() async {
                    if (!await s.changeLock(v) && mounted) {
                      message(
                        'App lock was not changed. Authentication is required.',
                      );
                    }
                  }),
          ),
          InterfaceSwitchListTile(
            title: const Text('Use biometrics'),
            secondary: const AppIcon(AppIconRole.biometric),
            subtitle: Text(
              s.biometric
                  ? 'Use enrolled fingerprint or face, with device screen lock as fallback.'
                  : 'Enroll a supported biometric in device settings. Device screen lock remains available.',
            ),
            value: s.useBiometrics,
            onChanged:
                busy || !s.supported || (!s.biometric && !s.useBiometrics)
                ? null
                : (v) => changeSecurity(biometrics: v),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: DropdownButtonFormField<int>(
              icon: const AppIcon(AppIconRole.expand),
              key: ValueKey('lock-delay-${s.lockDelay}-$busy'),
              initialValue: s.lockDelay,
              decoration: const InputDecoration(
                labelText: 'Lock after leaving',
              ),
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 0, child: Text('Immediately')),
                DropdownMenuItem(value: 30, child: Text('30 seconds')),
                DropdownMenuItem(value: 60, child: Text('1 minute')),
                DropdownMenuItem(value: 300, child: Text('5 minutes')),
              ],
              onChanged: busy || !s.supported || !s.lockEnabled
                  ? null
                  : (v) => changeSecurity(delay: v),
            ),
          ),
          InterfaceSwitchListTile(
            title: const Text('Protect screen content'),
            subtitle: const Text(
              'Block screenshots and hide the recent-apps preview while App lock is on.',
            ),
            value: s.protectScreen,
            onChanged: busy || !s.supported
                ? null
                : (v) => changeSecurity(screen: v),
          ),
          InterfaceSwitchListTile(
            title: const Text('Hide notification content'),
            subtitle: const Text(
              'Use a generic message instead of private details. Clears existing notifications when changed.',
            ),
            value: s.hidePreviews,
            onChanged: busy || !s.supported
                ? null
                : (v) => changeSecurity(previews: v),
          ),
          if (!s.secureDevice && s.supported)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Set a device PIN, pattern, or password before enabling app lock.',
              ),
            ),
          ListTile(
            title: const Text('Device security settings'),
            trailing: const AppIcon(AppIconRole.externalLink, size: 20),
            onTap: busy || !s.supported
                ? null
                : () => run(s.platform.securitySettings),
          ),
          if (s.lockEnabled)
            Padding(
              padding: const EdgeInsets.all(8),
              child: OutlinedButton.icon(
                onPressed: busy ? null : s.conceal,
                icon: const AppIcon(AppIconRole.lock),
                label: const Text('Lock now'),
              ),
            ),
        ]),
      ];
    }
    return [
      panel([
        InterfaceSwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          title: const Text('Allow notifications'),
          subtitle: Text(
            !s.supported
                ? 'Available on Android'
                : !s.notificationAllowed
                ? 'Blocked or not yet allowed by Android'
                : s.notifications
                ? 'Enabled on this device'
                : 'Off in this app',
          ),
          value: s.notifications && s.notificationAllowed,
          onChanged: busy || !s.supported
              ? null
              : (v) => run(() => s.changeNotifications(v)),
        ),
        ListTile(
          title: const Text('System notification settings'),
          trailing: const AppIcon(AppIconRole.externalLink, size: 20),
          onTap: busy || !s.supported
              ? null
              : () => run(s.platform.notificationSettings),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: DropdownButtonFormField<String>(
            icon: const AppIcon(AppIconRole.expand),
            initialValue: testCategory,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Test category'),
            items: [
              for (final category in widget.categories)
                DropdownMenuItem(
                  value: category.id,
                  child: Text(category.label),
                ),
            ],
            onChanged: busy
                ? null
                : (v) => setState(() => selectedTestCategory = v!),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: OutlinedButton.icon(
            onPressed:
                busy ||
                    !s.supported ||
                    !s.notifications ||
                    !s.notificationAllowed ||
                    s.categories[testCategory] != true ||
                    s.channelAllowed[testCategory] != true
                ? null
                : () => run(() async {
                    await s.platform.testNotification(testCategory);
                    if (mounted) message('Test notification sent.');
                  }),
            icon: const AppIcon(AppIconRole.notifications),
            label: const Text('Send test notification'),
          ),
        ),
      ]),

      const AppGap(24),
      heading('CATEGORIES'),
      const Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: Text(
          'Control which updates can notify you. Test each category above; each category is controlled separately.',
        ),
      ),
      panel([
        for (final category in widget.categories)
          InterfaceSwitchListTile(
            title: Text(category.label),
            subtitle: Text(
              s.channelAllowed[category.id] == false
                  ? 'Blocked in Android settings'
                  : category.description,
            ),
            value: s.categories[category.id] == true,
            onChanged: busy || !s.supported
                ? null
                : (v) => run(() => s.category(category.id, v)),
          ),
      ]),
      const AppGap(16),
      const Text(
        'Sound, vibration, and lock-screen delivery are managed in Android notification settings.',
      ),
    ];
  }

  Widget heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 18),
    child: Text(
      text,
      style: TextStyle(
        fontSize: s.pixel ? 10 : 11,
        letterSpacing: s.pixel ? .3 : 2.2,
        fontWeight: FontWeight.w600,
        color: s.accent,
      ),
    ),
  );
  Widget panel(List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );

  Widget swatches(
    List<Palette> colors,
    int selected,
    ValueChanged<int> onTap,
    String kind,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final count = (constraints.maxWidth / 82).floor().clamp(2, 6);
      final width = (constraints.maxWidth - (count - 1) * 12) / count;
      return Wrap(
        spacing: 12,
        runSpacing: 18,
        children: List.generate(colors.length, (i) {
          final chosen =
              colors[i].color == (kind == 'base' ? s.base : s.accent);
          return SizedBox(
            width: width,
            child: Semantics(
              selected: chosen,
              button: true,
              label: '${colors[i].name} $kind color',
              child: ExcludeSemantics(
                child: Column(
                  children: [
                    Material(
                      color: Theme.of(context).colorScheme.surface,
                      shape: interfaceShape(context, radius: 20),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: ValueKey('$kind-${colors[i].name}'),
                        borderRadius: interfaceRadius(context, 20),
                        onTap: busy ? null : () => onTap(i),
                        child: Container(
                          height: 76,
                          width: width,
                          decoration: ShapeDecoration(
                            shape: interfaceShape(
                              context,
                              radius: 20,
                              side: BorderSide(
                                color: chosen
                                    ? s.accent
                                    : Theme.of(context)
                                          .colorScheme
                                          .outlineVariant,
                                width: chosen ? 2 : 1,
                              ),
                            ),
                          ),
                          child: Center(
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: colors[i].color,
                                shape: s.pixel
                                    ? BoxShape.rectangle
                                    : BoxShape.circle,
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: .15),
                                ),
                              ),
                              child: chosen
                                  ? AppIcon(
                                      AppIconRole.confirm,
                                      size: 18,
                                      color:
                                          colors[i].color.computeLuminance() >
                                              .179
                                          ? Colors.black
                                          : Colors.white,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const AppGap(8),
                    Text(
                      colors[i].name.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9,
                        letterSpacing: .7,
                        color: chosen
                            ? s.accent
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      );
    },
  );
}
