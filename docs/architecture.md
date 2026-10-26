# Code layout

| Path | Responsibility |
| --- | --- |
| `lib/main.dart` | App entrypoint |
| `lib/src/bootstrap/` | Dependency assembly |
| `lib/src/core/` | Application contracts, coordination and infrastructure |
| `lib/src/features/` | Feature domain/application code and typed ports |
| `lib/src/experience/` | Screens and presenters |
| `lib/src/catalog/`, `lib/src/media/`, `lib/src/reading/` | Catalog, playback and reading contracts/adapters |
| `android/app/src/main/kotlin/com/bugdeployer/multiplexr/` | Android persistence, storage, playback and plugin host |
| `android/app/src/main/cpp/` | QuickJS JNI bridge and vendored engine |
| `packages/app_shell/` | Reusable shell, components and theme compiler |
| `packages/multiplexr_plugin_sdk/` | Plugin author tools, contracts and examples |
| `test/` | Flutter/domain tests and synthetic fixtures |
| `tool/` | Architecture checks and fixture tooling |
| `docs/` | Public build and authoring guides |

Application code depends on ports; native adapters implement them. Bootstrap connects the two. Presenters expose the state needed by screens. Existing adapter files remain in their current modules where moving them would add churn without changing ownership.

The architecture checker tracks import direction and known presenter ownership. It is a guard against dependency drift, not proof that every abstraction is ideal. New application/domain code should remain testable without Flutter.

AppShell does not depend on media models or collection routes. Its platform interface is implemented by the host. The JavaScript SDK is also independent of Flutter and Android; its fake host is a testing utility, not an untrusted-code sandbox.

Android owns media/file permissions and durable persistence. Plugins receive scoped handles and bounded projections. They cannot use raw database handles or replace authentication screens. Themes only control supported presentation tokens; accessibility and explicit user preferences take priority.
