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
3. **Degrade gracefully.** Unknown elements, attributes, and CSS are skipped;
   they never fail parsing or rendering. Not breaking on real-world files is
   more valuable than strict conformance.

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
| `<symbol>` | ✅ instantiated via `<use>` |
| `<path>`, `<rect>`, `<circle>`, `<ellipse>`, `<line>`, `<polyline>`, `<polygon>` | ✅ |
| `<linearGradient>`, `<radialGradient>`, `<stop>` | ✅ (`stop-color`, `stop-opacity`, `offset`) |
| `<text>`, `<tspan>` | ✅ `text-anchor`, multi-line `<tspan>` |
| `<style>` | ✅ id / class / tag selectors |
| `<filter>` | ✅ `feGaussianBlur` (SVG 1.1) + `feDropShadow` (SVG 2.0) |
| `<animate>`, `<animateTransform>`, `<set>` | ✅ SMIL subset (see below) |
| `<image>` | ✅ inline data-URI rasters (no external URLs) |
| `<switch>`, `<a>`, `<foreignObject>`, `<font>` | ❌ out of scope |
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
| `fill` | ✅ color, `none`, `url(#gradient/#pattern)` |
| `fill-rule` | ✅ `nonzero` / `evenodd` |
| `fill-opacity` | ✅ |
| `stroke` | ✅ color, `none`, `url(#gradient/#pattern)` |
| `stroke-width` | ✅ (`px`, `%`) |
| `stroke-opacity` | ✅ |
| `stroke-linecap`, `stroke-linejoin`, `stroke-miterlimit` | ✅ |
| `stroke-dasharray`, `stroke-dashoffset` | ✅ |
| `opacity` | ✅ |
| `clip-path` / `clip-rule` | ✅ local `url(#…)` |
| `mask` | ✅ local `url(#…)` |
| `filter` | ✅ local `url(#…)` |
| `transform` | ✅ `matrix`, `translate`, `rotate`, `scale`, `skewX`, `skewY` |
| `gradientTransform`, `gradientUnits`, `spreadMethod` | ✅ |
| `xlink:href` / `href` inheritance | ✅ |
| `display` | ✅ `inline` / `block` / `none` |
| `visibility` | ✅ `visible` / `hidden` / `collapse` |
| `currentColor` | ✅ resolved via `color` |
| `font-family`, `font-style`, `font-weight`, `font-size` | ✅ (`px` / `%` / `em`) |
| `marker-start`, `marker-mid`, `marker-end` | ✅ |
| `color`, `paint-order`, `vector-effect` | ❌ out of scope |

Color values: hex (`#rgb`/`#rgba`/`#rrggbb`/`#rrggbbaa`), named, `rgb()`, `rgba()`, `argb()`, `hsl()`, `hsla()`.

### CSS

- Inline `style="…"` ✅
- `<style>` blocks with id / class / tag selectors ✅
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
- `<switch>`, `<a>`, `<foreignObject>`, `<font>`, `<solidColor>`, `<cursor>`.
- Full text model: `textPath`, per-glyph `x`/`y` lists,
  `alignment-baseline`/`dominant-baseline`, `textLength`/`lengthAdjust`.
- CSS cascade: specificity, `inherit` resolution, combinators, `!important`,
  `@media`, `@font-face`.
- Nested `<svg>` viewports.
- `paint-order`, `color`, `vector-effect`.
- Full SMIL engine (event `begin`, `additive`/`accumulate`, `calcMode`, `fill="freeze"`).
- Length units: `px`/`pt`/`pc`/`in`/`cm`/`mm`/`%` supported; `ex`/`rem`/`ch`/`vw`/`vh`/`vmin`/`vmax` out of scope (`em` only for `font-size`).

## Degradation policy

- Unknown elements are skipped (not errors).
- Unknown attributes and properties are ignored.
- Malformed values on non-essential attributes are ignored; malformed
  *geometry* fails loudly (it is a content bug).
- The goal is to render as much of a real-world file as possible and never crash.

## Relationship to the standards (reference)

| Standard | Notes |
|---|---|
| **SVG 1.1 (Full)** | The Icon Profile is a subset of SVG 1.1. Coverage is high for the features icons use; the rest (text, filters, scripting, CSS) is intentionally omitted. |
| **SVG Tiny 1.2** | Closest in *philosophy* (drops `filter`/`mask`/`pattern`/`marker`/`symbol`), but Tiny *mandates* SMIL animation and has its own text model — neither is adopted here. |
| **SVG 2.0** | Almost entirely out of scope; tracked only for reference (`vector-effect`, `paint-order`, mesh gradients, geometry-as-CSS, `feDropShadow`). |

> These standards are for orientation only. SVGRenderKit does not claim formal
> conformance to any of them — it implements the **Icon Profile** above.

## How conformance is measured

Conformance to the Icon Profile is measured by **golden-image / snapshot tests**
over real icon sets, not by the W3C SVG test suite:

- A test fixture bundles a corpus of real icons (Feather, Lucide, Material,
  Tabler, and Figma / Sketch / Illustrator exports).
- Each icon is rendered off-screen and compared to a reference PNG (per-pixel
  tolerance, multiple `scale` factors: 1x / 2x / 3x).
- The pass metric is "icon sets that render pixel-accurately", tracked in CI.
- New icons that fail are triaged as either bugs or new profile features.

See `Task.md` (Phase 9) for the concrete work items.
