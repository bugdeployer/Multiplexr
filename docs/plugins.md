# Writing plugins

Plugins are signed JavaScript packages. Multiplexr controls installation, permissions, host calls and UI rendering. No metadata provider is bundled with the app.

## Start with an example

For a new plugin repository, choose **Use this template** on [multiplexr-plugin-template](https://github.com/bugdeployer/multiplexr-plugin-template). It includes a settings example, build/signing scripts, tests and release automation.

To try the examples included in the SDK:

Use Node.js 22 or newer:

```sh
cd packages/multiplexr_plugin_sdk
npm ci
npm test
npm run typecheck
node bin/plugin.js build examples/notes-tool /absolute/new/notes.json
node bin/plugin.js validate /absolute/new/notes.json
```

The Notes example declares a controlled UI destination without requiring media services. `examples/platform-demo` covers more contribution families. A plugin directory contains a `manifest.json` and the JavaScript entry file named by it.

The manifest identifies the publisher namespace, version, protocol range, required/optional capabilities and contributions. Use namespaced IDs such as `org.example.notes:welcome`. Request only the capabilities needed by your plugin. Unknown required capabilities cause installation or invocation to fail.

Bundled code can use the `AppShell` helper global. Protocol 1 retains `multiplexrEntry` as its entrypoint and `multiplexr-plugin-1` as its signed envelope identifier. These names are protocol identifiers; do not rename them in a plugin.

## Sign the package

Generate a P-256 EC key outside the repository, then sign the intermediate build:

```sh
openssl ecparam -name prime256v1 -genkey -noout -out /private/publisher.pem
node bin/plugin.js sign /absolute/new/notes.json /absolute/new/notes.mpx.json /private/publisher.pem
```

For network access, append the exact approved HTTPS origins to the sign command. Keep the publisher key private and reuse it for updates from the same publisher. Output paths must be new files. Intermediate proof artifacts are not installable signed packages.

Install the signed file from Plugins & themes. Review the publisher, requested permissions and destinations before enabling it. A signature identifies the signing key; it does not establish that the code is trustworthy. Never include service credentials in a manifest or bundle. Configure credentials through the host's approved credential setup.

## Contracts and limits

See the [API reference](../packages/multiplexr_plugin_sdk/API.md), [TypeScript declarations](../packages/multiplexr_plugin_sdk/src/index.d.ts) and [manifest schema](../packages/multiplexr_plugin_sdk/schemas/manifest.schema.json). Executable families include metadata/artwork/source providers, import/export handlers, library tools, UI contributions, events and session hooks. Settings sections are declarative manifest contributions. Hosts may support different subsets.

Invocations are synchronous and bounded. There is no Node runtime, `fetch`, filesystem API or persistent JavaScript event loop. Use the supported host methods and opaque handles. Validate inputs and outputs, respect cancellation and revision conflicts, and treat unavailable capabilities as expected errors.

Tests can import `multiplexr_plugin_sdk/testing`. Never execute untrusted packages in Node's VM; production containment belongs to the Android sandbox. Test keys/fixtures in this repository are not publisher credentials for real packages.

## Reuse in another app

Run `npm pack` in the SDK directory and install the resulting archive in your author project. Import `multiplexr_plugin_sdk/app-shell` for the app-neutral API. Implement and test your own host runtime, permission gateway, contribution renderer and persistence. Installing the author SDK does not add those services to an app.

Themes are separate data-only packages. See [theme authoring](themes.md).

## Provider HTTP

SDK 1.2 adds `httpJson`, JSON POST and host-managed `X-API-Key` credentials. These require Multiplexr 0.5.1 or newer. Declare `metadata.provide`, `http.request`, and `credentials.use` when needed. A metadata contribution should declare its supported `kinds` (for example `["movie", "television"]`). Collection access remains a separate user grant. Network packages are reviewed before enabling; GitHub package downloads may follow the GitHub release-asset redirect, without granting plugins access to that host.
