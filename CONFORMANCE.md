# SVG Standards Conformance

This document describes how much of the three main SVG standards
**SVGRenderKit** implements, and which one it is closest to.

> **Important:** these figures are *qualitative estimates* based on feature
> coverage in the source tree, **not** the result of running the official W3C
> SVG conformance test suites. Use them for orientation, not as a formal
> conformance claim.

The three standards compared here are:

1. **SVG 1.1 (Full)** — W3C Recommendation (2003, 2nd ed. 2011).
2. **SVG Tiny 1.2** — W3C Recommendation (2008), the mobile/embedded profile.
3. **SVG 2.0** — W3C Candidate Recommendation (2018), the modern revision.

## Summary

| Standard | Coverage | Notes |
|---|---|---|
| **SVG 1.1 (Full)** | **~40 %** (35–45 %) | Covers the core: geometry, paths, gradients, `clipPath`, basic text. Missing `filter`, `mask`, `pattern`, `marker`, `symbol`, animation, scripting, advanced text, and many stroke/CSS attributes. |
| **SVG Tiny 1.2** | **~60 %** (55–65 %) | The element set overlaps well (Tiny dropped `filter`/`mask`/`pattern`/`marker`/`symbol`). Missing Tiny's mandatory SMIL animation, multimedia, `solidColor`, and the Tiny text model. |
| **SVG 2.0** | **~25 %** (20–30 %) | The SVG 1.1 core geometry is present, but almost all SVG 2.0 additions are absent (mesh gradients, `vector-effect`, blending, `transform-origin`, geometry-as-CSS, etc.). |

## Closest standard

**SVG Tiny 1.2** is the closest *in profile philosophy and element overlap*,
because Tiny 1.2 removes exactly the "heavy" features SVGRenderKit also lacks
(`filter`, `mask`, `pattern`, `marker`, `symbol`). However, SVGRenderKit is not
conformant to any of the three standards: it is best described as a
**pragmatic subset of SVG 1.1 that resembles the Tiny profile**.

- Tiny 1.2 *requires* SMIL animation and multimedia — not implemented here.
- Tiny 1.2 has its own text model (`textArea`, `tbreak`, `text-align`) — not
  implemented here; text uses the SVG 1.1 model (single `CATextLayer`).
- Several SVG 1.1 *Basic/Tiny* features are implemented, so it also maps well
  onto the SVG 1.1 Tiny profile.

## Target standard

**SVG 1.1 is the target standard.** Conformance work is scoped to SVG 1.1
features first. SVG Tiny 1.2 and SVG 2.0 are tracked for reference only; their
specific additions (Tiny's `textArea`/`solidColor`/mandatory animation; 2.0's
`vector-effect`/`transform-origin`/mesh gradients) are out of scope for now.

> Note the distinction: **"closest profile"** (above) describes the current
> element overlap, while **"target"** describes what the project aims to
> conform to going forward. These differ — SVGRenderKit is closest to Tiny 1.2
> today, but SVG 1.1 is the direction of travel.

## Implemented features

### Elements

| Element | Status |
|---|---|
| `<svg>` | ✅ root only |
| `<g>` | ✅ |
| `<defs>` | ✅ |
| `<use>` | ✅ local `#ref` only |
| `<clipPath>` | ✅ |
| `<path>` | ✅ |
| `<rect>` | ✅ |
| `<circle>` | ✅ |
| `<ellipse>` | ✅ |
| `<line>` | ✅ |
| `<polyline>` | ✅ |
| `<polygon>` | ✅ |
| `<text>` | ✅ basic, single line |
| `<linearGradient>` | ✅ |
| `<radialGradient>` | ✅ |
| `<stop>` | ✅ (`stop-color`, `stop-opacity`, `offset`) |
| `<style>` | ✅ (id / class / tag selectors) |
| `<mask>`, `<pattern>`, `<marker>`, `<symbol>`, `<filter>` | ❌ |
| `<image>`, `<switch>`, `<a>`, `<foreignObject>`, `<font>` | ❌ |
| `<animate>`, `<set>`, `<animateTransform>`, etc. (SMIL) | ❌ |
| `<script>`, `<cursor>`, `<solidColor>`, `<textPath>`, `<tspan>` (multi) | ❌ |

### Path data commands

All commands are implemented, including elliptical arcs:

`M/m L/l H/h V/v C/c S/s Q/q T/t A/a Z/z` ✅

### Properties / attributes

| Property | Status |
|---|---|
| `viewBox`, `width`, `height` | ✅ (`px`, `%`) |
| `fill` | ✅ color, `none`, gradient `url(#…)` |
| `fill-rule` | ✅ `nonzero` / `evenodd` |
| `fill-opacity` | ✅ |
| `stroke` | ✅ color, `none` |
| `stroke-width` | ✅ (`px`, `%`) |
| `stroke-opacity` | ✅ |
| `opacity` | ✅ |
| `clip-path` | ✅ local `url(#…)` |
| `clip-rule` | ⚠️ enum declared, **not wired up** |
| `transform` | ✅ `matrix`, `translate`, `rotate`, `scale`, `skewX`, `skewY` |
| `gradientTransform`, `gradientUnits` | ✅ |
| `xlink:href` / `href` inheritance | ✅ (both spellings) |
| `display` | ✅ `inline` / `block` / `none` |
| `font-family`, `font-style`, `font-weight`, `font-size` | ✅ (`px` / `%` / `em`) |
| `preserveAspectRatio` | ✅ `meet`/`slice` + all aligns, `none` |
| `stroke-linecap`, `stroke-linejoin`, `stroke-miterlimit` | ✅ |
| `stroke-dasharray`, `stroke-dashoffset` | ✅ |
| `currentColor` | ⚠️ parsed, **not resolved** |
| `color`, `paint-order`, `vector-effect`, `marker-*`, `mask`, `filter` | ❌ |
| `text-anchor`, multi-line `<tspan>` layout | ❌ |

### CSS

- Inline `style="…"` attribute ✅
- `style` *element* blocks (`<style>` tag) ✅ with id / class / tag selectors
- `<style>` pseudo-classes, `@media`, cascade/`!important`, computed values ❌

## Limitations (why it is not 100 % on any standard)

- No `filter`, `mask`, `pattern`, `marker`, `symbol`.
- No SMIL animation or scripting.
- Basic text only: no `textPath`, no `text-anchor`, no multi-line `<tspan>`.
- `currentColor` is parsed but never resolved to a concrete color.
- `clip-rule` is declared but not applied.
- External `url(...)` resources are not loaded.
- Almost all SVG 2.0 additions are absent (see below).

## Improvement roadmap — targeting SVG 1.1

Ordered by expected **coverage gain per effort** against SVG 1.1 — the top
items are cheap and unlock a large share of real-world SVG 1.1 content.

| # | Feature | Effort | SVG 1.1 area |
|---|---|---|---|
| 1 | ✅ `preserveAspectRatio` (`meet`/`slice`, `xMidYMid`, …) | Low | Viewport / layout |
| 2 | ✅ `stroke-linecap`, `stroke-linejoin`, `stroke-miterlimit` | Low | Painting |
| 3 | ✅ `stroke-dasharray`, `stroke-dashoffset` | Low | Painting |
| 4 | `currentColor` resolution | Medium | Painting |
| 5 | `clip-rule` wiring (enum already exists) | Low | Clipping |
| 6 | `<symbol>` + `<use>` with `viewBox`/`width`/`height` | Medium-High | Structure |
| 7 | `text-anchor` + multi-line `<tspan>` | Medium | Text |
| 8 | `<mask>` | Medium | Compositing |
| 9 | gradient `spreadMethod` (`pad`/`reflect`/`repeat`) | Medium | Gradients |
| 10 | `<pattern>` | High | Painting |
| 11 | `<marker>` (arrowheads) | High | Painting |
| 12 | `<filter>` subset (`feGaussianBlur`, `feDropShadow`) | High | Filters |
| 13 | SMIL animation | Very High | Animation |

### Why this order

- **Tier 1 (#1–5)** is the highest ROI: `CAShapeLayer` already exposes
  `lineCap`, `lineJoin`, `miterLimit`, `lineDashPattern`, `lineDashPhase`, so
  most of these are one-line mappings. `currentColor` dominates icon sets
  (Feather, Material, Lucide), and `clip-rule` only needs wiring an existing
  enum into the mask path.
- **Tier 2 (#6–9)** unlocks sprite sheets and shaded artwork exported from
  Illustrator/Figma, which currently relies on `clipPath` + gradients but
  often also on `symbol`/`mask`/`spreadMethod`.
- **Tier 3 (#10–13)** rounds out SVG 1.1 coverage but is expensive; `<filter>`
  can be staged as a small, common subset first.

### Explicitly out of scope (for now)

- **SVG Tiny 1.2** additions: `textArea`/`tbreak`, `solidColor`, mandatory
  SMIL animation, `handler`/`listener`.
- **SVG 2.0** additions: `vector-effect`, `transform-origin`, mesh gradients,
  `paint-order`, geometry-as-CSS.
