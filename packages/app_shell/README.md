# AppShell

Shared Flutter shell, navigation, settings controls and theme compiler. This package does not depend on Multiplexr media models or routes.

This directory contains the public AppShell source used by Multiplexr. Build and modify it here; no access to a separate repository is required.

Initialize the shell before creating the app. A host supplies destinations and implements `ShellPlatform` for persistence, authentication and device settings. Unsupported platforms must report unsupported capabilities rather than simulate authentication. `example` is a separate Notes app.

`lib/app_shell.dart` exposes the shell/components. `lib/coordination.dart` exposes pure Dart mutation coordination. `lib/theme_sdk.dart` exposes theme authoring and validation.

Run `flutter pub get`, `flutter analyze` and `flutter test` here. See [architecture](../../docs/architecture.md), [theme authoring](../../docs/themes.md) and [contributing](../../CONTRIBUTING.md).

Project code is GPL-3.0-only. Font/icon licenses remain in `assets/`.
