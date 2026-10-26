<p align="center"><img src="assets/branding/multiplexr-android-icon.png" width="96" alt="Multiplexr icon"></p>

# Multiplexr

A local media library for Android. Organize movies, TV, videos, music, audiobooks, ebooks and comics in collections, then play or read them in the app.

[Download 0.5.0](https://github.com/bugdeployer/Multiplexr/releases/tag/v0.5.0) · [Build from source](docs/development.md) · [Contribute](CONTRIBUTING.md)

## What works

- Collections with multiple folders, search, filters and grid/list views.
- Video and audio playback, queues, resume positions, subtitles and external player selection.
- Music albums, artists and playlists; audiobook chapters, bookmarks and sleep timers.
- EPUB, TXT, PDF, CBZ and image-chapter readers with saved progress.
- Library backup and restore, collection locks and local/global browsing spaces.
- Importable themes and plugins with reviewed permissions.

No media, online metadata provider or shared provider key is included. Local files and manual metadata editing work without plugins. Folder access uses Android's system picker. Collection locks control access in the app; they do not encrypt files.

## Status

0.5.0 is the first release from this public repository. The app is still being tested with larger libraries and different Android devices. Back up your library before installing a new version. Plugin interfaces are versioned separately from the app.

Android is the supported target. The application ID is `com.bugdeployer.multiplexr`; older preview installations used a different ID and will not be updated in place. Export a library backup from the old installation and reconnect folders after restoring it.

## Development

The UI and application code use Flutter/Dart. Android adapters use Kotlin, Media3, SQLite and the Storage Access Framework. Plugins run through an isolated QuickJS host.

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

See [development](docs/development.md) for native tests and release signing, and [architecture](docs/architecture.md) for module boundaries.

## SDKs

The repository includes both reusable packages:

- [Plugin SDK](packages/multiplexr_plugin_sdk): JavaScript helpers, TypeScript contracts, manifest validation, bundling and signing. [Author guide](docs/plugins.md).
- [AppShell](packages/app_shell): shared Flutter components and a data-only theme compiler. [Theme guide](docs/themes.md).

SDK archives are attached to the release. The plugin SDK has no runtime npm dependencies. A different host app must implement its own sandbox, permissions, persistence and host services.

## License

Project code is licensed under [GPL-3.0-only](LICENSE). Third-party code, fonts and icons retain their own licenses; see [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES.md).
