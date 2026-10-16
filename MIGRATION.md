# Migration guide

## `open` → `public` for non-instantiable classes; `SVGBaseGradient` as an extension point (Unreleased)

`SVGCache`, `SVGParser`, `SVGUtils` and `SVGTransform` changed from `open` to `public`. Their
initializers are not accessible outside the module, so an external subclass could never be created or
used by the library; in practice nothing breaks. The only source-breaking case is an external
`class Foo: SVGUtils { override class func … }` (or an `override` of `SVGParser.getLayer`,
`SVGCache.resetCache`) — remove the subclass and call the library's implementation, or wrap it in your
own helper type.

Everything else that was `open` is unchanged: `SVGView`, `SVGRoot`, `SVGOptions`,
`SVGSourceStyleElement` and the tag classes (`SVGObject`, `SVGShape*`, `SVGGTag`, …) keep a public
`init`, so they remain subclassable.

`SVGBaseGradient` is the supported place to plug in a custom gradient. Subclass it, override
`getGradientLayer(maskLayer:path:viewBox:currentColor:)` and read the now-public `stops`,
`gradientUnits`, `spreadMethod` and `transform`:

```swift
import SVGRenderKit

final class MyGradient: SVGBaseGradient {
    override func getGradientLayer(maskLayer: CALayer, path: UIBezierPath, viewBox: CGRect,
                                   currentColor: UIColor = .black) -> CALayer? {
        let layer = CAGradientLayer()
        layer.frame = path.bounds
        layer.colors = stops.map { $0.resolvedColor(currentColor: currentColor).cgColor }
        layer.locations = stops.map { NSNumber(value: $0.offset) }
        return layer
    }
}
```

If your subclass previously used `@testable import` to reach `stops`/`offset`/`stop_color`, switch to
the public properties (they are get-only outside the module).

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
| `SVGCache` | `open class SVGCache` | `open class SVGCache: @unchecked Sendable` | Nothing. Internal state is guarded by a lock (a serial queue before 1.3.1). A subclass must keep that guarantee. |
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
- `SVGRenderer.render(...)` (added in 1.3.0) is not main-actor isolated: call it from any context, `await` the `async` variant or
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
