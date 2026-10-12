# SVGRenderKit

SVGRenderKit is a lightweight SVG renderer for iOS written in Swift. It parses
SVG documents and renders them into `CALayer` hierarchies, so the result can be
embedded into any `UIView` and re-colored at runtime.

The library originated as a fork of [SwiftSVG](https://github.com/mchoe/SwiftSVG)
and has since been rewritten around an object-tree parser (powered by
[SWXMLHash](https://github.com/drmohundro/SWXMLHash)).

## Documentation

API documentation is generated with [DocC](https://www.swift.org/documentation/docc/)
from the `///` comments in the source and published to [GitHub Pages](https://ihodorchenko.github.io/SVGRenderKit/).

## Requirements

- iOS 15.0+
- Swift 5.9+ (Swift 5 and Swift 6 language modes; see [MIGRATION.md](MIGRATION.md))
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
    .package(url: "https://github.com/ihodorchenko/SVGRenderKit.git", from: "1.1.1")
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

### From another bundle or a file URL

```swift
// Framework or Swift Package resources.
svgView.set(SVGName: "icons/my-icon.svg", bundle: Bundle.module)

// A file on disk (re-parsed automatically when the file changes).
svgView.set(svgURL: fileURL)
```

### From a string or data

```swift
svgView.svgString = "<svg viewBox=\"0 0 24 24\">…</svg>"

// or
svgView.set(svgData: data, name: "my-icon")
```

Assigning `nil` to `SVGName` or `svgString` clears the view. `SVGView` can also be
created in a storyboard/XIB (set `SVGName` in Interface Builder). Use it from the main
thread like any `UIView`; loads requested from other threads are marshalled onto it.

### Rendering to PNG / JPEG / PDF data

`SVGRenderer` renders an SVG straight to `Data` without creating an `SVGView`. It runs off the
main thread and is available as `async` and as a completion-handler method:

```swift
let png = try await SVGRenderer.render(.string(markup), size: CGSize(width: 64, height: 64), scale: 3)
let jpg = try await SVGRenderer.render(.url(fileURL), format: .jpeg(quality: 0.8), background: .white)
let pdf = try await SVGRenderer.render(.data(data, name: "icon"), format: .pdf)

SVGRenderer.render(.string(markup), format: .png) { result in   // called on a background queue
    // result: Result<Data, Error>
}
```

Without `size` the document's own size is used. JPEG has no alpha and defaults to a white background.

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

### Elements

- Shapes: `<path>`, `<rect>`, `<circle>`, `<ellipse>`, `<line>`, `<polyline>`, `<polygon>`, `<text>`, `<image>` (inline data-URI)
- Structure: `<g>`, `<defs>`, `<use>`, `<symbol>`, `<switch>` (fallback child)
- Paint servers: `<linearGradient>`, `<radialGradient>`, `<pattern>`, `<mask>`, `<clipPath>`, `<marker>`
- Filters: `feGaussianBlur`, `feDropShadow`, and the `feOffset`/`feFlood`/`feColorMatrix` drop-shadow chain (Figma/Sketch)
- Animation: SMIL subset (`<animate>`, `<animateTransform>`, `<set>`)

### Properties

- `fill`, `stroke`, `fill-rule`, `clip-rule`, `opacity`, `fill-opacity`, `stroke-opacity`
- `stroke-width` (`px`/`%`), `stroke-linecap`/`linejoin`/`miterlimit`, `stroke-dasharray`/`dashoffset`
- `clip-path`, `mask`, `filter` (local `url(#…)`)
- `transform` (`matrix`, `translate`, `rotate`, `scale`, `skewX`, `skewY`) and `gradientTransform`
- `gradientUnits`, `spreadMethod`, `xlink:href` inheritance
- `display`, `visibility`, `currentColor` (resolved via `color`)

### Colors

Hex (`#rgb`/`#rgba`/`#rrggbb`/`#rrggbbaa`), named, `rgb()`, `rgba()`, `argb()`, `hsl()`, `hsla()`, and `currentColor`.

### CSS

Inline `style="…"`, the `style` attribute, and `<style>` blocks with id / class / tag selectors.

### Fonts

`font-family`, `font-style`, `font-weight`, `font-size` (`px`/`%`/`em`), `text-anchor`, and multi-line `<tspan>`.

### Convenience

- Parser caching keyed by MD5
- Runtime re-coloring by element `id` / `class`, plus a global color-override mechanism

## Limitations

- iOS only (no macOS, tvOS, watchOS, or visionOS).
- External resources (web `url(...)` references) are not loaded.
- CSS cascade is out of scope: specificity, `inherit` resolution, combinators,
  pseudo-classes, `@media`, and `@font-face` are not evaluated.
- Full text model is out of scope: `textPath`, per-glyph `x`/`y` lists, and
  `alignment-baseline`/`dominant-baseline`.
- SMIL is a subset: event-based `begin`, `additive`/`accumulate`, `calcMode`, and
  `fill="freeze"` are not supported.
- Relative length units (`em`/`ex`/`rem`/`ch`/`vw`/`vh`) are not supported
  (`em` only for `font-size`).
- The full filter pipeline (`feMorphology`, `feComposite` operators beyond
  `in`/`out`, `feBlend` modes) is out of scope; Figma/Sketch drop-shadows are
  approximated without the `feMorphology` erosion step.
- Conditional-processing attributes on `<switch>` (`requiredFeatures`/
  `requiredExtensions`/`systemLanguage`) are not evaluated; the first child
  without them is rendered.
- `paint-order`, `vector-effect`, `color`, and `non-scaling-stroke` are not
  supported.

See [CONFORMANCE.md](CONFORMANCE.md) for the full icon-profile contract.

## Architecture

1. **XML** — `SVGParser` parses the document with SWXMLHash.
2. **Object tree** — the result is an object tree (`SVGRoot` → `SVGGroupObject` → shapes/gradients/clip paths), each node holding its attributes and resolved style (`SVGSourceStyleElement`).
3. **Render** — each node builds a `CALayer` (`CAShapeLayer` for shapes, `CAGradientLayer` for gradients, `CATextLayer` for text).
4. **Layout** — `SVGView` scales and translates the layer to fit the view's bounds.

## Example app

The `Example` project is a gallery that renders every SVG bundled under
`Example/Example/data` (`svg_0.0` … `svg_3.0`). Open `Example/Example.xcodeproj`
and run the `Example` scheme — it consumes the library as a local Swift Package.
The gallery supports a light/dark/gray substrate color picker and a full-screen
detail view.

## Tests

The package includes a unit test suite covering parsing, the data model, colors,
vector math, filters, masks, patterns, gradients, and an on-the-fly render-parity
harness. Run it from the repository root:

```sh
xcodebuild test \
  -scheme SVGRenderKit \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

(Adjust the `name=` value to a simulator available on your machine.)

The render-parity test (`SVGRenderParityTests`) renders every icon in the bundled
corpus against Apple's CoreSVG on the fly (no committed golden images) and
compares them pixel-by-pixel within a tolerance. It gates on regressions — a crash,
a reference parse failure, or a divergence not accounted for in the triage
allowlist fails the build — while known limitations (text metrics, anti-aliasing,
8-digit hex, filter erosion) are reported without failing. CI runs the suite on
iPhone and iPad simulators and emits the corpus summary into the GitHub step
summary.

## License

MIT. See [LICENSE](LICENSE).

Based on [SwiftSVG](https://github.com/mchoe/SwiftSVG) by Michael Choe, and
bundles [SWXMLHash](https://github.com/drmohundro/SWXMLHash) and
[SwiftHash](https://github.com/onmyway133/SwiftHash) (MD5), both MIT-licensed.
