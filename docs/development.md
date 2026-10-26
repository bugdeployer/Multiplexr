# Development

## Requirements

- Flutter stable with Dart 3.13.5 or newer, compatible with `pubspec.yaml`.
- Android SDK and the NDK/CMake versions selected by the Gradle configuration.
- JDK 21 for the build tooling. Android source targets Java 17.
- Node.js 22+ for plugin SDK tools, and Python 3 for architecture checks.

Run `flutter doctor` before building. `pubspec.lock` and the SDK's `package-lock.json` are committed for reproducible dependency resolution.

## Checks

```sh
flutter pub get
flutter analyze
flutter test
python -m unittest discover -s tool -p 'test_*.py'
python tool/check_architecture.py --strict-architecture
flutter build apk --debug
```

For native unit tests:

Screenshot baselines are rendered on Windows. CI runs the eight tagged `golden` checks on Windows and the remaining suite on Linux. Use `flutter test --exclude-tags=golden` on Linux, or run `flutter test test/collection_experience_test.dart --tags=golden` on Windows for the image comparisons. Do not update baselines to hide platform rendering differences.

```sh
cd android
./gradlew :app:testDebugUnitTest
```

On Windows, use `gradlew.bat`. Instrumented tests require a device or emulator. Plugin isolation checks require a debug build configured with `-PpluginSandboxProof=true`; ordinary debug builds keep that proof service disabled.

For the plugin SDK:

```sh
cd packages/multiplexr_plugin_sdk
npm ci
npm test
npm run typecheck
npm run test:consumer
```

Run `flutter pub get`, `flutter analyze` and `flutter test` from `packages/app_shell` after changing shared components or theme behavior. Its `example` directory is a separate Notes app that does not import Multiplexr.

## Release signing

Create an Android signing key outside the repository. Add an ignored `android/key.properties` file:

```properties
storeFile=/absolute/path/to/release.jks
storePassword=YOUR_LOCAL_PASSWORD
keyAlias=release
keyPassword=YOUR_LOCAL_PASSWORD
```

Then run `flutter build apk --release`. Release builds fail when signing is not configured. Never commit this file or the keystore. Public release artifacts must be built from the tagged source, and checksums should accompany downloads.

The app's release version is in `pubspec.yaml`. Keep the Android build number increasing even when changing the visible version. SDK and theme protocol versions are separate.

## Device checks

Automated tests don't cover every OEM's background playback, Bluetooth, storage access, PiP, biometrics or process recovery behavior. Check those flows on the devices affected by a change. Record results in the pull request rather than adding private test logs or internal planning documents to the source tree.
