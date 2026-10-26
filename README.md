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

Add your own media through Android's folder picker. Plugins can provide metadata lookup.

## Status

Version **0.5.0**. Requires **Android 7.0 or newer**.

## Development

The UI and application code use Flutter/Dart. Android adapters use Kotlin, Media3, SQLite and the Storage Access Framework. Plugins run through an isolated QuickJS host.

```sh
flutter pub get
flutter analyze
flutter test --exclude-tags=golden
flutter build apk --debug
```

See [development](docs/development.md) for Windows screenshot checks, native tests and release signing, and [architecture](docs/architecture.md) for module boundaries.

## SDKs

The repository includes both reusable packages:

- [Plugin SDK](packages/multiplexr_plugin_sdk): JavaScript helpers, TypeScript contracts, manifest validation, bundling and signing. [Author guide](docs/plugins.md).
- [AppShell](packages/app_shell): shared Flutter components and a data-only theme compiler. [Theme guide](docs/themes.md).

SDK archives are available from [Releases](https://github.com/bugdeployer/Multiplexr/releases).

## License

Project code is licensed under [GPL-3.0-only](LICENSE). Third-party code, fonts and icons retain their own licenses; see [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES.md).
