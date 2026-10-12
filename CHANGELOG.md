# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 1.3.1

Performance release; there are no public API changes.

### Changed
- `SVGParser` no longer reads or XML-parses the source on a parser-cache hit.
- `SVGRenderer` rasterizes and encodes concurrently (capped at the core count) while parsing and layer
  building stay on the serial work queue; batches of renders scale with the available cores.
- `SVGCache` is a real LRU (a hit refreshes recency) guarded by a lock instead of a FIFO behind a
  serial queue.
- Pattern tiles, mask bitmaps, decoded embedded images and fonts are cached per document, so a pattern
  or mask shared by many shapes is rendered once. Luminance masks are converted with fixed-point math in
  place.
- Group `clip-path`/`mask` bounding boxes and marker vertices are computed only when needed.
- `SVGView` skips loads that were superseded while still queued, and no longer animates its layout
  transform implicitly.
- `SVGImageView` resolves color overrides only when it reloads.

### Fixed
- Path data parsing no longer triggers a CoreGraphics `no current point` error log for every command
  before the first `Z`, which dominated parse time (a 60-path, ~12k-segment map: ~1.4 s -> ~12 ms).
  The `d` scanner is a single pass over UTF-8 and no longer quadratic in the path length.
- `SVGLinearGradientLayer.draw` restores the graphics state it saves.
- Gradient stops are sorted only when needed, so a gradient shared by cached trees is no longer
  written on every use.

### Added
- Release-mode performance benchmarks (`SVGPerformanceTests`), `os_signpost` intervals around parse,
  layer building and rasterization, and a `Performance` GitHub workflow with `Scripts/perf_report.py`.

## 1.3.0

### Added
- `SVGRenderKitSwiftUI` product with `SVGImageView`, a SwiftUI wrapper around `SVGView` that renders
  bundled resources, markup, data or file URLs and reloads only when the source or overrides change.
- `SVGRenderer.render(_:size:format:scale:background:overrideElements:)` — render SVG (string, data or file URL)
  directly to PNG, JPEG or PDF `Data` without an `SVGView`, as an `async` method and a completion-handler method.

## 1.2.0

### Added
- Swift 6 language mode support alongside Swift 5.9+ (`swiftLanguageVersions: [.v5, .v6]`).
  See [MIGRATION.md](MIGRATION.md) for the API differences.

### Changed
- Public enums (`SVGFillRuleType`, `SVGClipRuleType`, `SVGFontStyle`, `SVGDisplaytype`,
  `SVGVisibility`, `SVGLineCap`, `SVGLineJoin`) and `Vector2` are `Sendable`;
  `SVGCache` and `SVGConfiguration` are `@unchecked Sendable`.
- `SVGLog.logger` access is now thread-safe.

## 1.1.1

### Added
- `SVGView.set(SVGName:bundle:overrideElements:)` — load a bundled SVG from any `Bundle`
  (framework, Swift Package resources), not only `Bundle.main`.
- `SVGView.set(svgURL:overrideElements:)` — render an SVG file at a URL.
- `SVGView` can be created from a storyboard/XIB (`init(coder:)`), including the
  `@IBInspectable` `SVGName`.

### Fixed
- Parser cache is keyed by content: the same `name` with different markup/data no longer
  returns a stale tree; file URLs are keyed by path plus file size and modification date.
- CSS precedence (inline > `<style>` > presentation attributes), `clip-rule` inside `clipPath`,
  text paint, and more tolerant color / paint / class / text-position parsing.
- Hardening against crashes and data races on untrusted SVG.
- Faster path-data parsing for glyph-dense documents.
- Assigning `nil` to `SVGName`/`svgString` clears the view and cancels an in-flight load.
- The update notification (e.g. theme change) reloads views created from `svgString`,
  `svgData`, a URL or a custom bundle; the last requested source wins.
- `SVGConfiguration.isParserCacheEnabled` is now thread-safe.
- Loads requested off the main thread are marshalled onto it instead of racing on view state.
- Pattern tiles are re-rasterized when a view gets its size after loading or grows
  noticeably, instead of staying blurry.

### Changed
- `SVGView` loads run on a single serial background queue (bounded thread count, no
  interference between views sharing a cached document).
- `SVGView` should be used from the main thread, like any `UIView`.

## 1.1.0

### Added
- Group-compositing of `opacity`/`clip-path`/`mask`/`filter` + `visibility` on `<g>`.
- `<image>` inline data-URI rasters.
- `hsl()`/`hsla()` colors.
- `feOffset`/`feFlood` drop-shadow primitive chain (SVG 1.1) and `feDropShadow` (SVG 2.0).
- Figma/Sketch drop-shadows: the `feOffset` + `feColorMatrix` tint chain drives the
  `CALayer` shadow (color + opacity from the color matrix).
- `<switch>` conditional processing: renders the first child without
  `requiredFeatures`/`requiredExtensions`/`systemLanguage`, so Illustrator
  exports (fallback art wrapped in `<switch>` + `<foreignObject>`) now render.

### Fixed
- 8-digit hex colors parsed as `#RRGGBBAA` (CSS/SVG 2.0 order).
- Gradient `xlink:href` inheritance now honors attributes explicitly set on the
  referencing gradient (`gradientUnits`, `spreadMethod`, `gradientTransform`).
- `gray_ruble.svg` — removed a duplicate `id` attribute that CoreSVG rejected.

### Changed
- CI now gates corpus parity on regressions (crash, reference parse failure, or an
  un-annotated divergence) and emits the annotated summary into the GitHub step summary.
- Parity triage classifies `display:none` and `<switch>` fixtures as *reference-limited*:
  CoreSVG does not implement these SVG 1.1 features.

## 1.0.1

### Added
- On-the-fly render-parity tests against Apple's CoreSVG (no committed golden images).
- Corpus-based parity triage over the bundled icon set.
- `mask`, `pattern`, `marker`, and `symbol` element support.
- A `filter` subset (`feGaussianBlur`, `feDropShadow`).
- Initial SMIL animation support.
- `clip-rule`, `currentColor`, `stroke-dasharray`/`dashoffset`, `stroke-linecap`/`linejoin`/`miterlimit`, and `preserveAspectRatio` support.
- `text-anchor` and multi-line `tspan`.
- Example app: lazy-loaded icon gallery and full-screen detail view.

### Fixed
- CSS class selectors from `<style>` now apply to shapes.
- Path parsing: uppercase `E` exponents, leading-zero integers, dangling command
  letters, relative first commands, leading whitespace, and smooth curves following `Z`.
- Basic shapes accept length units (`px`, `pt`, `pc`, `in`, `cm`, `mm`, `%`) and reject negative radii.
- Gradients: radial `fx`/`fy`, `objectBoundingBox` mask localization, percentage
  stroke-width, tiny viewBoxes, and `spreadMethod` parity with CoreSVG.
- Clip paths, masks, and patterns honor their `*Units` and region attributes.
- Markers honor `orient`/`markerUnits` and render `marker-start`/`marker-mid`.
- Unsupported units and invalid stroke/color attributes degrade gracefully instead
  of failing the whole document.

## 1.0.0

Initial public release.
