# SVG Conformance & Icon Profile

> **SVGRenderKit is an icon renderer, not a browser.** Its contract is a
> documented **Icon Profile** — the subset of SVG that real icon sets actually
> use — rather than formal conformance to any full W3C standard.

## Guiding principles

1. **Target = real icon sets, not the W3C test suite.** The goal is to render
   the SVG produced by icon sets (Feather, Lucide, Material, Font Awesome,
   Tabler, Heroicons, …) and by Figma / Sketch / Illustrator exports correctly.
2. **Measure by golden images, not by a conformance percentage.** "~40 % of
   SVG 1.1" is not a useful number here: most of the remaining 60 % never
   appears in icons. Correctness = N icon sets render pixel-accurately.
3. **Degrade gracefully.** Unknown elements, attributes, and CSS are skipped; they
   never fail parsing or rendering. An element with unusable geometry (a `<rect>`
   without a size, an unparsable `d`, …) is skipped with a log and the rest of the
   document still renders. Only a document that is not SVG at all — no `<svg>`
   element — fails to parse, so the caller gets an error. Not breaking on real-world
   files is more valuable than strict conformance.

## The Icon Profile (contract)

### Elements

| Element | Status |
|---|---|
| `<svg>` | ✅ root (`viewBox`/`width`/`height`/`preserveAspectRatio`) |
| `<g>`, `<defs>` | ✅ |
| `<use>` | ✅ local `#ref`, incl. `<symbol>` with `viewBox` |
| `<clipPath>` | ✅ |
| `<mask>` | ✅ alpha + luminance masking |
| `<pattern>` | ✅ tiled fill |
| `<marker>` | ✅ marker-start/mid/end (`auto` orientation) |
| `<symbol>` | ✅ instantiated via `<use>` (no viewport clip: `overflow` is out of scope) |
| `<path>`, `<rect>`, `<circle>`, `<ellipse>`, `<line>`, `<polyline>`, `<polygon>` | ✅ |
| `<linearGradient>`, `<radialGradient>`, `<stop>` | ✅ (`stop-color`, `stop-opacity`, `offset`) |
| `<text>`, `<tspan>` | ✅ `text-anchor`, multi-line `<tspan>` with its own styles, `xml:space`, solid `stroke`, `opacity`/`clip-path`/`mask`/`filter`; gradient/pattern stroke ❌ |
| `<style>` | ✅ id / class / tag selectors, applied in document order (matched on the element itself, including containers such as `<g class="…">`, `<use>`, `<text>`, `<image>`) |
| `<filter>` | ✅ `feGaussianBlur` (SVG 1.1, baked into the layer) + `feDropShadow` (SVG 2.0) + `feOffset`/`feFlood`/`feColorMatrix` drop-shadow chain (Figma/Sketch) |
| `<animate>`, `<animateTransform>`, `<set>` | ✅ SMIL subset (see below) |
| `<image>` | ✅ inline data-URI rasters (no external URLs), with `clip-path`/`mask`/`filter` |
| `<switch>` | ✅ renders first child without `requiredFeatures`/`requiredExtensions`/`systemLanguage` |
| `<a>`, `<foreignObject>`, `<font>` | ❌ out of scope |
| `<textPath>`, `<script>`, `<cursor>`, `<solidColor>` | ❌ out of scope |

### Path data

All path commands are supported, including elliptical arcs:

`M/m L/l H/h V/v C/c S/s Q/q T/t A/a Z/z` ✅

### Properties

| Property | Status |
|---|---|
| `viewBox`, `width`, `height` | ✅ (`px`, `%`) |
| `preserveAspectRatio` | ✅ `meet`/`slice`, all aligns, `none` |
| `version`, `baseProfile` | ✅ parsed (stored) |
| `fill` | ✅ color (named, `transparent`, hex, `rgb`/`hsl`), `none`, `url(#gradient/#pattern)` with an optional fallback |
| `fill-rule` | ✅ `nonzero` / `evenodd` |
| `fill-opacity` | ✅ (number or `%`, clamped to [0, 1]) |
| `stroke` | ✅ same paints as `fill` |
| `stroke-width` | ✅ (`px`, `%`) |
| `stroke-opacity` | ✅ (number or `%`, clamped to [0, 1]) |
| `stroke-linecap`, `stroke-linejoin`, `stroke-miterlimit` | ✅ |
| `stroke-dasharray`, `stroke-dashoffset` | ✅ |
| `opacity` | ✅ (number or `%`, clamped to [0, 1]) |
| `clip-path` / `clip-rule` | ✅ local `url(#…)` |
| `mask` | ✅ local `url(#…)` |
| `filter` | ✅ local `url(#…)` |
| `transform` | ✅ `matrix`, `translate`, `rotate`, `scale`, `skewX`, `skewY` |
| `gradientTransform`, `gradientUnits` | ✅ |
| `spreadMethod` | ⚠️ `pad` only — `reflect`/`repeat` render as `pad`, matching CoreSVG |
| `xlink:href` / `href` inheritance | ✅ |
| `display` | ✅ `inline` / `block` / `none` |
| `visibility` | ✅ `visible` / `hidden` / `collapse` |
| `currentColor` | ✅ resolved via `color` |
| `color` | ✅ (resolves `currentColor`) |
| `font-family`, `font-style`, `font-weight`, `font-size` | ✅ (`px` / `%` / `em`) |
| `marker-start`, `marker-mid`, `marker-end` | ✅ |
| `paint-order`, `vector-effect` | ❌ out of scope |

Color values: hex (`#rgb`/`#rgba`/`#rrggbb`/`#rrggbbaa`), named, `rgb()`, `rgba()`, `argb()`, `hsl()`, `hsla()`.

### CSS

- Inline `style="…"` ✅
- `<style>` blocks with id / class / tag selectors ✅ (matched on the element itself,
  so a matched `<g>` styles itself and is inherited by its descendants)
- Cascade, specificity, `inherit` resolution, descendant/combinator selectors,
  pseudo-classes, `@media`, `@font-face` ❌ out of scope

### Animation (SMIL subset)

- `animate` (`opacity`/`fill`/`stroke`), `animateTransform`
  (`rotate`/`translate`/`scale`), `set` ✅
- `from`/`to`, `values`, `keyTimes`, `repeatCount`, `begin` ✅
- Event-based `begin`, `to`-only, `additive`/`accumulate`, `calcMode`,
  `fill="freeze"` ❌ out of scope

## Explicitly out of scope (browser features)

- Scripting, DOM, and events.
- External resource loading (`url(...)` to the network).
- `<a>`, `<foreignObject>`, `<font>`, `<solidColor>`, `<cursor>` (conditional-processing attributes on `<switch>` are not evaluated; the first child without them is rendered).
- Full text model: `textPath`, per-glyph `x`/`y` lists,
  `alignment-baseline`/`dominant-baseline`, `textLength`/`lengthAdjust`.
- CSS cascade: specificity, combinators, `@media`, `@font-face`. `inherit` is honoured for
  `visibility`, `clip-rule`, `fill-rule` and `text-anchor` (the inherited value stays); an
  `!important` flag is accepted but carries no priority — the value applies as an ordinary
  declaration.
- Nested `<svg>` viewports.
- `paint-order`, `vector-effect`.
- Full SMIL engine (event `begin`, `additive`/`accumulate`, `calcMode`, `fill="freeze"`).
- Full filter pipeline: `feMorphology` (erode/dilate), `feComposite` operators
  beyond `out`/`in`, `feBlend` modes, and multi-input filter graphs. Figma/Sketch
  drop-shadows are recognized via their `feOffset` + `feColorMatrix` tint chain,
  but the `feMorphology` erosion step is approximated away (the shadow is not inset).
- Length units: `px`/`pt`/`pc`/`in`/`cm`/`mm`/`%` supported; `ex`/`rem`/`ch`/`vw`/`vh`/`vmin`/`vmax` out of scope (`em` only for `font-size`).

## Degradation policy

- Unknown elements are skipped (not errors).
- Unknown attributes and properties are ignored.
- Malformed values on non-essential properties are logged and ignored; the
  shape still renders with its remaining/default paint. `opacity` / `fill-opacity` /
  `stroke-opacity` accept a percentage (`50%`) and are clamped to [0, 1] like CSS.
- A malformed *geometry* value (a `<rect>` without `width`/`height`, a `<circle>`
  without a radius, an unparsable `d`) skips only that element — the rest of the
  document still renders. An odd trailing coordinate in `points` is dropped (SVG 2);
  fewer than two complete pairs is unusable geometry and skips the element.
- A missing local reference (`url(#…)` for fill / stroke / `clip-path` / `mask` /
  `filter` / `marker`) is logged and skipped: paint becomes `none`, or the paint's
  own fallback (`fill="url(#grad) #fff"`). A gradient without stops paints nothing
  (SVG 1.1 §13.2).
- A `<use>` whose target is missing, external, or part of a reference cycle is
  dropped with a log; the rest of the document still renders.
- Nothing above fails the whole document: the goal is to render as much of a
  real-world file as possible and never crash.

## Relationship to the standards (reference)

| Standard | Notes |
|---|---|
| **SVG 1.1 (Full)** | The Icon Profile is a subset of SVG 1.1. Coverage is high for the features icons use; the rest (text, filters, scripting, CSS) is intentionally omitted. |
| **SVG Tiny 1.2** | Closest in *philosophy* (drops `filter`/`mask`/`pattern`/`marker`/`symbol`), but Tiny *mandates* SMIL animation and has its own text model — neither is adopted here. |
| **SVG 2.0** | Almost entirely out of scope; tracked only for reference (`vector-effect`, `paint-order`, mesh gradients, geometry-as-CSS, `feDropShadow`). |

> These standards are for orientation only. SVGRenderKit does not claim formal
> conformance to any of them — it implements the **Icon Profile** above.

## How conformance is measured

Conformance to the Icon Profile is measured by **on-the-fly render-parity tests**
against Apple's CoreSVG over a corpus of real icons, not by the W3C SVG test suite:

- A test fixture bundles a corpus of real icons (Illustrator, Sketch, and
  Figma exports, plus hand-crafted edge cases) under `Example/Example/data`.
- Each icon is rendered off-screen by both `SVGView` (under test) and CoreSVG
  (the oracle), then compared pixel-by-pixel within a tolerance. No committed
  golden PNGs — the reference is produced at test time to keep the repo small.
- The pass metric is "icons that render pixel-accurately vs CoreSVG", tracked in CI
  (iPhone + iPad) and surfaced in the GitHub step summary.
- Fixtures that use features CoreSVG does not implement (`display:none`, `<switch>`,
  8-digit hex) are classified as *reference-limited* rather than failures.
- The same kit rasters are also judged by a second, *browser* oracle (`WKWebView`, B122):
  `Scripts/webkit-parity.sh` renders the corpus in a web view (from the Example app — a bare
  test bundle cannot host WebKit's WebContent process) and the test then compares *both*
  oracles against the identical raster, so a behaviour CoreSVG shares with the kit, or hides,
  is visible in one report. That side reports as `WEBKIT_SUMMARY` and is triaged the same way.
  CI runs it on pushes to main, manually, and on pull requests labelled `webkit`
  (`webkit-parity.yml`).
- Besides the summary counts, every accepted divergence keeps its differing-pixel fraction in
  `.github/parity-fixtures.txt` / `.github/webkit-fixtures.txt` (`Scripts/check-fixtures.sh`): a
  fixture that gets worse, or a new failing one, fails the gate.
- New icons that fail are triaged as either bugs or new profile features.

The live corpus summary is reported by CI in the GitHub step summary; see [README.md](README.md#tests) for how the suite is run.

## Deliberate divergences from the reference renderers

**Policy.** We follow the SVG specification wherever the specification and the browser (WebKit)
agree. We keep CoreSVG's behaviour only where it looks better in the app: for example, a trial of
mixing linear-gradient stops in sRGB, as the spec and browsers do, was dropped because the native
gradient layer draws noticeably faster on screen. Every remaining difference from a reference
renderer (CoreSVG on iOS, WebKit) is listed in the table below, together with the reason.

| Behaviour | This kit | CoreSVG / WebKit |
|---|---|---|
| A radial gradient's focal point outside its end circle | moved onto the circle (SVG 1.1 §13.2.3), so a `pad` gradient paints its whole area | left where it is: a cone is painted and the area outside it stays transparent (SVG 2 / Canvas semantics) |
| Stop interpolation within a linear gradient | mixed in the renderer's own space, like CoreSVG; kept because the native gradient layer is faster on screen and the browser oracle disagrees only at gradient interiors | mixed in sRGB (WebKit; the `color-interpolation` default) — CoreSVG mixes like this kit |
| `spreadMethod="reflect"` / `"repeat"` | rendered as `pad`, like CoreSVG; not implemented (not needed for icons) | WebKit repeats / reflects the gradient vector; CoreSVG renders `pad` |

`fr` (the focal circle radius, SVG 2) is supported; CoreSVG ignores it, while WebKit and this
kit agree on it.
