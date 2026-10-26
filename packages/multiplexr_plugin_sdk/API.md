# Protocol 1 reference and compatibility policy

Protocol 1 defines the version-1 envelope, signed package and listed methods. Compatible additions must be optional and negotiated; changing required fields, meanings or permissions requires a new protocol/host major. Unknown required capabilities, unsupported host/protocol ranges and executable theme contributions reject explicitly. Package updates must increase numeric semver and use reviewed publisher identity; rollback is a separate host action. A plugin version is independent of SDK version.

All calls are synchronous bounded host RPC inside an invocation. Scope/title/file/session handles are opaque and temporary. They are never database IDs or paths. `createHost` throws PluginError with a documented ErrorCode; cancellation suppresses late results. No fetch, Node, native handles or general filesystem API exists.

| Host method | Required capability | Contract |
| --- | --- | --- |
| runtime.ping | runtime.ping | Empty params → protocol/runtime |
| catalog.titles | catalog.read | Scope handle, limit 1–100 and optional revision-bound cursor → title page |
| catalog.title | catalog.read | Title handle → title/revision projection |
| catalog.fields | catalog.read | Title handle → this publisher namespace's user-owned fields |
| catalog.propose | catalog.propose | Title handle, expected revision, idempotency key and replaceTags/mergeFields → pending proposal; separate host confirmation commits |
| http.get | http.request; credentials.use when requested | Approved HTTPS URL, optional credential=true (Bearer) or credential='apiKey' (X-API-Key) → status/body; host injects credential and filters private destinations/redirects |
| http.post | http.request; credentials.use when requested | Same origin and credential policy as GET; JSON body ≤8 KiB; redirects rejected |
| storage.read/write | storage.private | Schema 1–100000, key and string/null value → string/null; publisher-owned quota |
| settings.register | settings.read | Empty params → declared section IDs |
| settings.effective | settings.read | Field ID and ordered authorized lineage → effective value/source/revision |
| settings.propose/reset | settings.write | Field ID, authorized address, expected revision and value for propose → new revision |
| settings.changes | settings.read | afterRevision → revision/resyncRequired; re-query values |
| imports.read | import.parse | Host-created file handle → bounded UTF-8 text/MIME |

TypeScript declarations in src/index.d.ts specify parameter/result types, unions, settings fields and UI/session positions. Settings inheritance is app → collection → group → title; opaque handles are resolved by the host. Secrets have no script read API and do not belong in portable settings or private strings.

Contribution families: metadata.provider, artwork.provider, source.provider, import.handler, export.handler, library.tool, event.handler, ui.action, ui.section, ui.destination, settings.section, session.hook and media.descriptor. Metadata fields are a bounded descriptive allowlist; artwork becomes host-reviewed bytes; source discovery cannot mint persistent grants; tools/imports propose selection-scoped edits; export writes through a user-chosen destination. Controlled UI permits text/groups/actions, not arbitrary widgets or security replacement. Events are active-app best-effort resync notifications with bounded retries, not persistent background scheduling. Sessions support confirmed pause/resume/time seek on supported host engines. Descriptors annotate only known host engines/extensions; plugins cannot load decoders.

Theme packages are separate format-2 JSON, previewed by the Themes tab. See examples/themes and the app-shell theme contract. They run no code and do not grant capabilities.

## Limits

Code ≤64 KiB; signed envelope ≤512 KiB; runtime message ≤64 KiB and JSON nesting ≤24. Runtime CPU budget 250 ms excluding host waits, 15-second wall watchdog and 16-second client deadline. Host RPC waits ≤11 seconds; each HTTP call has a 10-second deadline. Private data ≤1 MiB per publisher namespace, value ≤32 KiB. Invocations expose at most 512 title handles/64 calls; pending interpreter queue ≤16. Events deliver at most four automatic attempts per plugin per minute, with origin suppression and resync. HTTP is HTTPS/443 at exact approved origins with no ambient cookies/proxy; response and invocation limits apply. A provider requiring long asynchronous requests is outside this synchronous contract.

## Independent build

Run npm ci, npm test and npm run typecheck in this directory. Run `node bin/plugin.js build examples/platform-demo <new-proof.json>`; then sign with a private P-256 key using the documented CLI. Install the signed package in Settings → Plugins & themes, review its permissions and enable it. Keep the publisher key outside the app/repository. Examples contain synthetic data and no commercial metadata provider. FakeHost is a contract test double and deliberately does not emulate privileged HTTP, private storage or confirmed mutations; unsupported calls fail explicitly.

Provider publishers are responsible for the terms of any third-party services or content they use.

Metadata providers can declare a nonempty `kinds` array to limit selection to supported media kinds. Older declarations without `kinds` retain their broad scope. `httpJson(host, url, credential?, body?)` performs a mediated GET, or JSON POST when a body is supplied, and maps authentication, rate-limit and malformed-response errors to stable codes. Scripts never receive credential bytes.
