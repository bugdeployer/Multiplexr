# Writing themes

Themes are JSON packages. They can change colors, typography, component shapes, borders, spacing, density, motion, and supported semantic icons. They cannot execute code or replace native Android/system UI.

## Start with a package

Copy an example from `packages/app_shell/theme_examples`: rounded-modern, square-minimal or stepped-retro. Give the copy a unique lowercase ID and a short name. Keep `format: "multiplexr-theme"` and `version: 2`.

The package contains `dark` and `light` palette defaults, presentation `tokens`, and optional embedded `assets`. Use the example token names rather than inventing new fields. User preferences and accessibility settings override package defaults.

## Validate and build

From the AppShell directory, with Flutter and Python available:

```sh
cd packages/app_shell
flutter pub get
python tool/theme_author.py validate theme_examples/rounded-modern.theme.json
python tool/theme_author.py build theme_examples/rounded-modern.theme.json /absolute/new/my-theme.json
```

The tool uses the production compiler and asset decoders. It refuses to overwrite existing output. Import the built JSON through Plugins & themes and review both light/dark previews and credits before applying it.

Flutter tools can import `package:app_shell/theme_sdk.dart`. `ThemePackageAuthor.validate` validates/prepares a package, `build` returns canonical JSON, and `asset` creates an attributed embedded asset descriptor with a SHA-256 digest.

## Assets

Assets are embedded PNG icons or TTF/OTF fonts. Each needs a relative `assets/` path, MIME type, base64 data, SHA-256 digest, author and license. Include required license text. External asset URLs and paths outside the package are not accepted.

The current compiler accepts up to 64 assets, two fonts and 3 MiB of decoded asset data; total JSON is limited to 4 MiB. See [theme tokens](../packages/app_shell/lib/src/theme/theme_tokens.dart) for supported fields and limits. Don't increase limits from a theme package.

## Check appearance

Check light and dark modes, large text, RTL layout, reduced motion, buttons, text fields, menus, cards and selection states. Text must remain readable against the actual surface. Check content near rounded/stepped card edges and progress indicators. Theme changes must not alter media access or application behavior.

Document fonts, reading preferences and external players have their own settings. The app theme styles reader/player controls where supported, not the document itself.
