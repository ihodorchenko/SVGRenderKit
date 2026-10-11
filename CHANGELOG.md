# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
