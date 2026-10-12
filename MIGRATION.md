# Migration guide

## Swift 5.9 and Swift 6.0 support (1.2.0)

SVGRenderKit now builds in both the Swift 5 and the Swift 6 language mode
(`swiftLanguageVersions: [.v5, .v6]`, `swift-tools-version:5.9`). Supported toolchains:
Swift 5.9 and later (Xcode 15+). Packages that opt in to strict concurrency
(`-strict-concurrency=complete`) or the Swift 6 language mode compile against the library
without concurrency diagnostics coming from its public types.

Most changes are source compatible. The list below covers every API difference.

### Public API changes

| API | Before | Now | What to do |
| --- | --- | --- | --- |
| `SVGFillRuleType`, `SVGClipRuleType`, `SVGFontStyle`, `SVGDisplaytype`, `SVGVisibility`, `SVGLineCap`, `SVGLineJoin` | `enum …: String` | `enum …: String, Sendable` | Nothing; additive. |
| `Vector2` | `Hashable` | `Hashable, Sendable` | Nothing; additive. |
| `SVGCache` | `open class SVGCache` | `open class SVGCache: @unchecked Sendable` | Nothing. Internal state is already guarded by a serial queue. A subclass must keep that guarantee. |
| `SVGConfiguration` | `public final class` | `public final class …: @unchecked Sendable` | Nothing. Internal state is already lock/queue guarded. |
| `SVGLog.logger` | stored `static var` | computed `static var` backed by a lock | Nothing; get/set syntax is unchanged. Reads and writes are now thread-safe. |

### Internal changes (no API impact)

- The `static var default` values of the enums above (`SVGFillRuleType.default`, …) are now
  `static let` (they were never mutated). These are `internal`, so this affects only the
  library itself.
- `SVGTextTag.screenScale` and `SVGLog.logger` are stored in a lock-protected `LockedBox`
  instead of a bare `static var`, because Swift 6 rejects mutable global state that is not
  isolated.
- `SVGView` hands the parsed `SVGParser` and the built `CALayer` from its background load
  queue to the main thread through an `@unchecked Sendable` wrapper. The ownership rule is
  unchanged: both objects are only touched on the main thread after the hand-off.

### Things to keep in mind when adopting Swift 6 mode in your app

- `SVGView` is a `UIView`, so it is `@MainActor`-isolated like every UIKit view. Create it and
  call `set(...)` / assign `SVGName` / `svgString` from the main actor. The load itself still
  runs on a background queue and calls from other threads are still marshalled onto main.
- `SVGRenderer.render(...)` is not main-actor isolated: call it from any context, `await` the `async` variant or
  use the completion handler (invoked on a background queue — hop to main yourself before touching UI). `SVGSource`
  and `SVGRenderFormat` are `Sendable`.
- Passing an `SVGView` or an `SVGParser` across isolation domains is not allowed (neither is
  `Sendable`). `SVGConfiguration.shared`, `SVGCache.s` and the enums above can be used from
  any isolation domain.
- A custom `SVGLogger` is called from whatever thread logs; make its implementation
  thread-safe. The protocol itself is **not** required to be `Sendable`, so existing loggers
  keep compiling.

### Example app

The example project stays on Swift 5 language mode (`SWIFT_VERSION = 5.0`); nothing needs to
change there.
