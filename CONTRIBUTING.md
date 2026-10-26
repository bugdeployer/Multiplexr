# Contributing

Bug reports, fixes, tests and documentation changes are welcome. For a larger change, open an issue first so we can agree on scope.

## Report a bug

Include your Android version, device, app version, steps to reproduce and expected behavior. A screenshot or a short recording helps with layout bugs. Remove media paths, credentials and personal information from logs. Do not upload your library or copyrighted media as a fixture.

## Send a change

1. Fork the repository and branch from `main`.
2. Use a short descriptive branch name, such as `fix/reader-resume` or `docs/theme-assets`.
3. Keep the change focused. Explain the problem, the resulting behavior and how you checked it in the pull request.
4. Run the relevant checks and add regression coverage for bug fixes.

Use the Dart formatter for Dart code. Keep comments about constraints, tradeoffs or non-obvious behavior. Prefer descriptive names and small interfaces over broad utility modules. Don't reformat unrelated files or add dependencies without explaining why.

## Boundaries

Domain and application code must not depend on Flutter widgets or concrete Android adapters. Assemble dependencies in bootstrap. Shared components belong in AppShell; media policies belong in the app. Plugin declarations never grant permissions by themselves. Themes contain data, not executable code.

See [architecture](docs/architecture.md), [development](docs/development.md), [plugin authoring](docs/plugins.md) and [theme authoring](docs/themes.md).

Use synthetic media and temporary test publisher keys. Never commit signing keys, tokens, library backups or user files. Report security problems through [SECURITY.md](SECURITY.md).

By contributing, you agree that your changes are distributed under this repository's GPL-3.0-only license. Keep existing attribution and third-party license notices.
