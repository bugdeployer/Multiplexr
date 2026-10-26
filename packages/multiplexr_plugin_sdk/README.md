# Plugin SDK

JavaScript helpers, TypeScript contracts and author tools for protocol-1 plugins. Requires Node.js 22+. No runtime npm dependencies, Flutter or Android imports.

```sh
npm ci
npm test
npm run typecheck
npm run test:consumer
npm pack
```

Install the tarball in another author project, or use the CLI directly from this directory. `multiplexr_plugin_sdk/app-shell` exports the app-neutral API; `app-shell-plugin` and `multiplexr-plugin` are CLI aliases.

Read the [author guide](https://github.com/bugdeployer/Multiplexr/blob/main/docs/plugins.md) and [API reference](API.md). Start with `examples/notes-tool` for a controlled UI contribution, or `examples/platform-demo` for other families. The fake host is for tests, not containment of untrusted plugins.

The package is distributed through repository releases; npm registry publication is not configured. SDK version 1.1.0 and protocol 1 are independent of the app's 0.5.0 release. Project code is GPL-3.0-only.
