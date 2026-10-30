# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 2.0.1 - 2026-10-30

### Fixed
- `SVGView` no longer loses a document's SMIL animations when the layer tree is built before the view
  is in a window (`viewDidLoad`, a collection view cell configured before it is enqueued, or any
  load whose main-thread install is delayed): Core Animation discards the animations of a layer tree
  that is committed while it is not in a render tree, and attaching the view later did not bring
  them back, so such a document stayed static for its whole lifetime. The build now collects the
  animations (`SVGOptions.defersAnimationAttach`) and `SVGView` attaches them on the main thread
  once the tree is installed and the view has a window, keeping the timeline epoch so the animation
  does not restart (`SVGViewAnimationAttachTests`). `SVGParser.getLayer` called directly still
  attaches the animations during the build, as before.

- A `linearGradient` with `gradientUnits="userSpaceOnUse"` now paints the whole element when an
  ancestor `transform` moves it. The gradient's raster window was the `viewBox`, which lives in the
  element's own coordinate space: a moving element (a wave group scrolling across a logo) left the
  part outside the window unpainted and the layer underneath showed through — a pale letter that
  flickered as the element moved. The window now also covers the element's own bounds; because the
  gradient is painted through the element's silhouette a larger window never paints anything extra,
  and documents whose shapes already fit the viewBox still render pixel-identically
  (`SVGUserSpaceGradientBoundsTests`). The radial `userSpaceOnUse` window has the same limitation
  and is not covered by this fix.

### Internal
- The parity corpus skips documents that animate (`CorpusLoader.hasRenderingAnimation`, a
  `PARITY_SKIP` line names each one): a static raster of them is not comparable across the three
  renderers — CoreSVG draws the base state, the WebKit oracle draws the SVG-as-image at an arbitrary
  moment of the timeline, and the kit rasters its model state. The Example gallery still shows them
  and the corpus summary is back to `total=1618` (`ParityCorpusAnimationTests`).

## 2.0.0 - 2026-10-23

A major release that narrows the public API to what a client can actually use, removes the 1.4.0
deprecation shims, and closes the crash and robustness findings of a follow-up audit. Rendering is
unchanged except where listed under Fixed. See [MIGRATION.md](MIGRATION.md).

### Changed (breaking)
- The object model (tags, `SVGRoot`, container protocols), the custom-gradient extension point
  (`SVGBaseGradient`, `SVGGradientStop`, `RadialGradientLayer`) and the vendored SWXMLHash are no
  longer public: nothing outside the module could create or plug in any of them. `SVGSourceStyleElement`
  is `public`, not `open`.
- Removed the deprecated 1.4.0 shims (`…Ovveride…` colour overrides, `set(…fill_colors:)`, global `MD5`).
- Removed the unused `SVGParseString.SVGParseStringkCompletion` and the unused SWXMLHash type-conversion
  extensions (705 lines).
- The parsed DOM is released as soon as the object tree is built (it used to live as long as the parser
  and its cache entry), and tags no longer keep their `XMLElement`.

### Internal
- Typed lookups in `SVGGroupObject`/`SVGRoot` share one generic helper; one `UncheckedSendable`.
  `SVGStylePropertyCoverageTests` pins that every style property is carried by `combine`/`set(element:)`
  (a key-path table instead of the hand-written lists made `getLayer` ~4x slower in a Release A/B).
- `Scripts/check-fixtures.sh` gates the differing fraction of every failing parity fixture
  (`.github/parity-fixtures.txt`, `.github/webkit-fixtures.txt`); two stale triage entries removed.
- Latin sub-letters in `B133`/`B124` references; source comments, scripts and the demo app are English.
- `Scripts/run-tests.sh` skips the Debug benchmarks by default (`PERF=1` runs them); the WebKit oracle runs
  in CI from `webkit-parity.yml` (nightly, manually, or on a PR labelled `webkit`); the release workflow
  extracts the notes of a `## x.y.z - date` heading.
- Closed as not reproducible: the claim that `objectBoundingBox` gradients use Bézier control-point
  bounds (`UIBezierPath.bounds` is the geometric extent; pinned by `SVGGradientFillBBoxTests`).

### Fixed
- A very long `xlink:href` chain of gradients or patterns no longer overflows the stack: past
  `SVGInputLimits.maxHrefChainDepth` (32) links the chain is cut and the element degrades.
- Crashes on hostile numbers: `animateTransform` with `nan` values (and unbounded keyframes for huge
  angles — capped at 720 samples per segment), a mask or pattern on a shape with a `1e308` extent,
  and `font-weight` of `inf`/`1e308` all trapped in `Int(_:)`; they now degrade.
- A `<pattern>` that cannot produce a tile (for example one larger than 4096 px) left the shape filled
  with the default black; the fill is now `none`.
- A non-finite or negative `font-size` (`nan`, `inf`, `-1`) is ignored instead of leaving a NaN on the
  text layer. `SVGHostileNumbersTests` now feeds `nan`/`inf`/`1e308`/`1e30`/`-1`/`0`/`1e-320` to every
  numeric attribute of every supported element (1450 documents) and requires no trap.
- `SVGConfiguration.updateNotificationName` is now guarded by a lock (it was read from the notification
  thread without one).

### Removed
- Internal dead code: write-only `sourceStyle` on `SVGImage`/`SVGPath`, the unused
  `SVGTags.addRange`/`exist` and an unreachable font fallback.

## 1.4.0 - 2026-10-16

An audit-and-hardening release: many rendering fixes against the SVG specification and a browser
oracle, graceful degradation instead of failing the whole document, limits for untrusted input and
a cleaned-up public API (deprecations are source compatible; see [MIGRATION.md](MIGRATION.md)).

### Added
- `SVGView.onLoadError` and `SVGImageView.onLoadError(_:)` report load failures. A failed load now
  clears the previous content instead of leaving the old image on a reused view, and a later reload
  (for example after a color-override change) retries the same source.
- Text: `stroke`/`stroke-width`/`stroke-opacity` on `<text>` and `<tspan>`, `opacity`/`clip-path`/
  `mask`/`filter` on text, `<tspan>` styles (`fill`, `font-weight`, classes, …), `xml:space`,
  `text-anchor` from `style`, `<style>` rules on `<text>` and `<image>`.
- Radial gradients: `fr` (focal radius) and a focal point outside the end circle is clamped onto it
  (SVG 1.1 §13.2.3).
- `<pattern>` honors `viewBox` and `href` inheritance; `patternTransform` acts on the pattern grid.
- Limits on untrusted input (`SVGInputLimits`): nesting depth, `<use>` depth and expansion budget,
  mask/pattern bitmap size, source size, image pixels, blur radius. Exceeding a limit skips the
  offending element with a log instead of overflowing the stack or exhausting memory.
  `SVGRenderer` throws for an output larger than 8192 px per side and an `async` render honors
  cancellation.
- Protection against self-references: a `<mask>`, `<pattern>`, `<clipPath>`,
  `<marker>` or `<filter>` that references itself is skipped, and fan-out `<use>` graphs no longer
  explode.
- Test and CI tooling: a second, browser (WebKit) parity oracle (`Scripts/webkit-parity.sh`), a
  parity gate for both oracles, a perf-regression gate with a CI baseline, `Scripts/run-tests.sh`.

### Changed
- `set(svgData:name:overrideElements:)` no longer has default values for its trailing parameters, so a call
  such as `set(svgData: data, name: "x")` is unambiguous (it resolves to the `fillColors` overload).
- `SVGCache`, `SVGParser`, `SVGUtils` and `SVGTransform` are now `public` instead of `open`. None of
  them has an initializer reachable from outside the module (`SVGCache` is a singleton with a private
  init, the others have internal or implicit-internal inits), so they could never be instantiated, and
  their `open` members were never reachable through a subclass the library would use. For callers
  this is not a source change: calling members, reading `SVGCache.s`, etc. is unchanged.
  **Breaking only for** code that declared `class X: SVGUtils` / `SVGParser` / `SVGCache` /
  `SVGTransform` and `override`s one of their members (`SVGUtils.trimmed`/`split`/`md5`/
  `pathEndInfo`/`pathVertices`/`bisector`, `SVGParser.getLayer`, `SVGCache.resetCache`); the
  library never dispatched through such a subclass, so the override had no effect.
- `SVGBaseGradient` is a supported extension point: it stays `open` with its `public required
  init(xmlElement:addDict:parent:)`, and what a subclass needs to implement `getGradientLayer` is now
  public: `stops`, `gradientUnits`, `spreadMethod`, `transform` (read-only outside the module), the
  `GradientUnits`/`SVGSpreadMethod` enums, and `SVGGradientStop.offset`/`stop_color`/
  `resolvedColor(currentColor:)`. Covered by a test that builds a subclass without `@testable`.
- Tag objects hold their `parent` as `unowned` (`public unowned var parent`); `SVGShapesContainer` is
  class-bound and a new `SVGGroupHosting` protocol shares the child-layer loop between containers.
- `spreadMethod` stays `pad`-only and linear-gradient stops stay mixed in the renderer's own space, like
  CoreSVG; both are documented as deliberate divergences in `CONFORMANCE.md`.

### Fixed
- The SVG `transform` list is composed left to right (`translate(10 0) matrix(2 0 0 2 0 0)` moves
  `(1, 0)` to `(12, 0)`), including `<use x y>`, `skewX`/`skewY` and `clipPathUnits="objectBoundingBox"`.
- Elliptical arc flags are read as single characters, so compact SVGO output (`a2 2 0 011 1`) renders.
- The document no longer fails because of one bad value: `fill="transparent"`/`inherit`, `opacity="50%"`,
  unknown `display`, odd `points`, a `<rect>` without a size, a circle without a radius, an unparsable
  `d`, a gradient without stops, a broken `url(#…)` for paint/clip/mask/filter/marker, and a `<use>`
  whose target is missing, external or part of a cycle are logged and skipped. The `<use>` cases used
  to throw; they now render the rest of the document. Only a document without an `<svg>` element fails.
- `<use>`: the composite (`opacity`, `clip-path`, `mask`, `filter`) is applied once on the instance;
  the referenced element keeps its own `transform`/clip/mask; ancestor styles and class/id selectors
  reach the content; inline `style` wins over the `fill` attribute; `x`/`y` accept units and percentages.
- `<image>` and `<g>` work inside `<use>`, `<symbol>`, `<mask>`, `<pattern>` and `<marker>`; children of
  these containers paint in document order; `<g>` inside `<clipPath>` is ignored (SVG 1.1 §14.3.5).
  `<image>` honors `clip-path`/`mask`/`filter` and is laid out in user space (`x`/`y`, `transform`).
  Base64 data with line breaks decodes.
- `<style>` is an ordered list of rules: later rules win, `.a, .b {}` is deterministic, comments and
  `@import`/`@charset`/`@media` no longer corrupt neighbours, rules apply in document order and on
  containers (`<g class="…">`), several `<defs>`/`<style>` blocks are all honored, ids are resolved
  document-wide (the first definition wins), forward `href` of gradients works and radial gradients
  inherit stops from linear ones.
- Inline `style`: the last duplicate wins, `!important` is accepted, `url(data:…;base64,…)` values survive,
  `style` overrides presentation attributes everywhere, `rgb(100%,0%,0%)`, `rgb(255 0 0 / 50%)` and
  space-separated `hsl()` parse, an invalid color declaration is ignored instead of becoming clear;
  `inherit` works for `clip-rule`, `visibility`, `text-anchor`.
- Masks, patterns and baked blur are rendered at the output scale and re-rendered on resize.
  `clip-path` and `mask` on one element combine instead of overwriting each other. `clip-path` in
  `userSpaceOnUse` moves with the element's `transform`.
- `objectBoundingBox` radial gradients are ellipses (`r·w × r·h`); a linear gradient with a skewed
  `gradientTransform` places its axis on the transformed level lines; gradient fills honor `evenodd`;
  a gradient `stroke` is positioned by the geometry bounding box (not the stroked outline) and honors
  dashes.
- Groups and `<use>` measure their bounding box on the transformed geometry (rotation and skew no longer
  inflate it); `visibility` can be overridden by a visible descendant; `fill-rule: inherit` keeps `evenodd`;
  default `stroke-miterlimit` is 4 (sharp corners no longer produce long spikes); `marker-mid` follows the
  bisector, curve tangents and sub-paths.
- `feGaussianBlur` is baked into the layer (`CALayer.filters` does not blur on iOS); the drop-shadow
  radius follows the CoreGraphics blur scale and a blurred element is not shadowed twice.
- Root `<svg>` size: a single `width`/`height` is completed from the `viewBox`, percentages resolve
  against it, `em`/`auto`/unknown units fall back to the `viewBox`, an unresolvable viewport degrades
  to a default size instead of throwing.
- `<pattern>` with `objectBoundingBox` units and a `viewBox` keeps a uniform fit; the tile phase is correct.
- SMIL `animateTransform` `rotate`/`skewX`/`skewY` are sampled in small steps with the centre from every
  value, comma-separated values and `keyTimes` work, and the animation timeline survives a re-render.
- `<text>`: default font size 16px, quoted `font-family`, weight/style applied to a named family,
  whitespace collapsed per SVG, run order and spacing around `<tspan>` kept (`Hello <tspan>world</tspan>` is no longer glued), text scales with the
  document's render scale.
- Caches: the parser cache is keyed by a full content digest and reset when override colors change
  (a parse that started before the reset cannot store a stale tree); tile and mask caches have a 96 MB
  byte budget; `SVGImageView` reloads when the file changes and stats the file at most every 0.5 s.
- The parsed object tree no longer leaks: `parent` references are `unowned`, so a document without
  `name:` and an evicted cache entry are freed.
### Deprecated
Each old name still works and forwards to the new one; the compiler offers a fix-it.

| Deprecated | Use instead |
| --- | --- |
| `SVGColors.addOvverideColors(colors:)` | `addOverrideColors(colors:)` |
| `SVGColors.setOvverideColors(colors:)` | `setOverrideColors(colors:)` |
| `SVGColors.addOvverideUIColors(colors:)` | `addOverrideUIColors(colors:)` |
| `SVGColors.setOvverideUIColors(colors:)` | `setOverrideUIColors(colors:)` |
| `SVGView.set(SVGName:fill_colors:)` | `set(SVGName:fillColors:)` |
| `SVGView.set(svgString:name:fill_colors:)` | `set(svgString:name:fillColors:)` |
| `SVGView.set(svgData:name:fill_colors:)` | `set(svgData:name:fillColors:)` |
| global `MD5(_:)` (String and `[UInt8]`) | `SVGUtils.md5(_:)` or CryptoKit |

### Removed
- Dead public API that was never reachable in a useful way: `SVGLinearGradientLayer` (unused by the
  renderer), `SVGParser.shouldParseSinglePathOnly`, and the ignored `force` parameter of the internal
  `set(styleStr:)`.

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
