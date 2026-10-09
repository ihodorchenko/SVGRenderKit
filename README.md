# SVGRenderKit

SVGRenderKit is a lightweight SVG renderer for iOS written in Swift. It parses
SVG documents and renders them into `CALayer` hierarchies, so the result can be
embedded into any `UIView` and re-colored at runtime.

The library originated as a fork of [SwiftSVG](https://github.com/mchoe/SwiftSVG)
and has since been rewritten around an object-tree parser (powered by
[SWXMLHash](https://github.com/drmohundro/SWXMLHash)).

## Documentation

API documentation is generated with [DocC](https://www.swift.org/documentation/docc/)
from the `///` comments in the source and published to GitHub Pages.

## Requirements

- iOS 15.0+
- Swift 5.9+
- Xcode 15+

## Platforms

- iPhone and iPad (iOS 15.0+)

## Installation

### Via Xcode

**File → Add Package Dependencies…** and enter the repository URL:

```
https://github.com/ihodorchenko/SVGRenderKit.git
```

### Via `Package.swift`

```swift
dependencies: [
    .package(url: "https://github.com/ihodorchenko/SVGRenderKit.git", from: "1.0.0")
]
```

Add `SVGRenderKit` to your target's dependencies.

### Local package

**File → Add Package Dependencies… → Add Local…** and select this repository's
folder, or drop the `Sources/SVGRenderKit` folder directly into your app target.

## Quick start

```swift
import SVGRenderKit

let svgView = SVGView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
svgView.set(SVGName: "icons/my-icon.svg")
view.addSubview(svgView)
```

`SVGView` keeps the SVG's aspect ratio and centers it inside its bounds.

## Usage

### From a bundled file

```swift
let svgView = SVGView()
svgView.set(SVGName: "icons/my-icon.svg")
```

### From a string or data

```swift
svgView.svgString = "<svg viewBox=\"0 0 24 24\">…</svg>"

// or
svgView.set(svgData: data, name: "my-icon")
```

### Re-coloring

Recolor individual elements by their `id` or `class`:

```swift
svgView.set(SVGName: "icons/icon.svg", fill_colors: [
    "#main": .red,
    ".accent": .blue
])
```

### Text and fonts

`<text>` elements are rendered, and `font-family`, `font-style`, `font-weight`,
and `font-size` (with `px`, `%`, and `em` units) are supported.

### Configuration

Global settings live in `SVGConfiguration`:

```swift
// Disable parser caching.
SVGConfiguration.shared.isParserCacheEnabled = false

// Reload cached views when a custom notification is posted.
SVGConfiguration.shared.updateNotificationName = NSNotification.Name("themeChanged")
NotificationCenter.default.post(name: NSNotification.Name("themeChanged"), object: nil)
```

### Override colors globally

Override a color across all parsed SVGs (e.g. for theming):

```swift
SVGColors.addOvverideUIColors(colors: ["#243B55": UIColor.label])
```

### Caching

Parser caching is enabled by default and keyed by name/path (MD5). Disable it
per-view or globally:

```swift
SVGView.isSVGParserUseCache = false           // global (through SVGCache)
SVGConfiguration.shared.isParserCacheEnabled = false
```

### Logging

Diagnostics go through `SVGLog`. Replace the logger to route them elsewhere:

```swift
struct MyLogger: SVGLogger {
    func log(_ message: String) { /* … */ }
}
SVGLog.logger = MyLogger()
```

## Features

- `<path>`, `<rect>`, `<circle>`, `<ellipse>`, `<line>`, `<polyline>`, `<polygon>`, `<text>`
- `<g>` groups, `<defs>`, `<use>`, and `<clipPath>`
- `<linearGradient>` and `<radialGradient>` (including `gradientTransform` and `xlink:href` inheritance)
- CSS via inline `style`, the `style` attribute, and `<style>` blocks (id / class / tag selectors)
- `fill`, `stroke`, `fill-rule`, `clip-rule`, `opacity`, `fill-opacity`, `stroke-opacity`, `stroke-width`
- `transform` on shapes and groups (`matrix`, `translate`, `rotate`, `scale`, `skewX`, `skewY`)
- Fonts: `font-family`, `font-style`, `font-weight`, `font-size` (`px` / `%` / `em`)
- Parser caching keyed by MD5
- Runtime re-coloring by element id / class, plus a global color-override mechanism

## Limitations

- iOS only (no macOS, tvOS, watchOS, or visionOS).
- No `<filter>`, `<mask>`, `<pattern>`, `<symbol>`, or `<marker>`; only `<clipPath>` is used for masking.
- External resources (web `url(...)` references) are not loaded.
- `currentColor` is parsed but not resolved.
- `font-size` supports `px`, `%`, and `em`; other units (`pt`, `rem`, `ex`) are not supported.
- Text layout is basic: a single `CATextLayer` with no `text-anchor`, multi-line `<tspan>` layout, or per-glyph styling.
- No animation support.

## Architecture

1. **XML** — `SVGParser` parses the document with SWXMLHash.
2. **Object tree** — the result is an object tree (`SVGRoot` → `SVGGroupObject` → shapes/gradients/clip paths), each node holding its attributes and resolved style (`SVGSourceStyleElement`).
3. **Render** — each node builds a `CALayer` (`CAShapeLayer` for shapes, `CAGradientLayer` for gradients, `CATextLayer` for text).
4. **Layout** — `SVGView` scales and translates the layer to fit the view's bounds.

## Example app

The `Example` project is a gallery that renders every SVG bundled in its `svg`
folder. Open `Example/Example.xcodeproj` and run the `Example` scheme — it consumes
the library as a local Swift Package.

## Tests

The package includes a unit test suite covering the parsing, data-model, color,
and vector-math APIs. Run it from the repository root:

```sh
xcodebuild test \
  -scheme SVGRenderKit \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

(Adjust the `name=` value to a simulator available on your machine.)

The tests cover `SVGColors`/`HTMLColors`, `SVGUtils`/`MD5`, `SVGFuncIRI`,
`SVGPaint`, `SVGLength`, `SVGError`, `Vector2`, `SVGParseString`,
`LinearGradientFixer`, font handling, configuration, and an end-to-end
parse-and-render smoke test. CI runs the suite on iPhone and iPad simulators.

## License

MIT. See [LICENSE](LICENSE).

Based on [SwiftSVG](https://github.com/mchoe/SwiftSVG) by Michael Choe, and
bundles [SWXMLHash](https://github.com/drmohundro/SWXMLHash) and
[SwiftHash](https://github.com/onmyway133/SwiftHash) (MD5), both MIT-licensed.
