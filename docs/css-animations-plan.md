# Plan: render and animate the original CSS-driven SVG (`folder_9/logo-ghost-wave-effect.svg`)

Status: **proposal**, not started. Depends on the two animation fixes released in 2.0.1 (see
"Prerequisites").

## 1. Goal

`Example/Example/data/folder_9/logo-ghost-wave-effect.svg` is a designer logo whose styling and motion
are pure CSS: one `<style>` block inside `<defs>`, class rules plus descendant selectors
(`.wA path`, `.wB path`, `.shine rect`), a gradient fill referenced from CSS, seven `@keyframes`,
`animation` shorthands with delays/easing/infinite loops, and two `@media` blocks
(`prefers-color-scheme: dark`, `prefers-reduced-motion: reduce`).

Today `SVGView` renders it with the wave/shine shapes in the SVG default **black** and with **no
motion**, while WebKit/CoreSVG render it (and Quick Look animates it) as designed. The
profile-adapted copy `logo-ghost-wave-effect-fixed.svg` already looks and animates correctly, but it
is a converted asset — it does not make the original file work.

**Goal:** the original file, unmodified, renders and animates through `SVGView` like it does in
WebKit, and the class of files it represents (designer-exported CSS-animated logos) works for future
icons too. The converted copy stays in the example as a reference/fallback.

## 2. Current state and prerequisites

Released in 2.0.1 (both are needed by this plan):

1. **SMIL animations were not playing** — Core Animation drops animations of a layer tree committed
   outside a render tree; `SVGOptions.defersAnimationAttach` + `SVGView` attach after the install
   (`SVGViewAnimationAttachTests`). Any CSS-animation work must reuse that path.
2. **`userSpaceOnUse` linear gradients were clipped to the `viewBox` window**, so a moving wave group
   showed a pale letter as it left the window (`SVGUserSpaceGradientBoundsTests`). CSS animations on
   gradient-filled shapes hit the same code path.
3. **Animated documents are excluded from the pixel corpus** (`CorpusLoader.hasRenderingAnimation`,
   `PARITY_SKIP`) because no static frame of them is comparable across CoreSVG, WebKit and the kit.
   The animation test strategy below follows from this.

What already works for the original file: `<style>` blocks inside the root `<defs>` are resolved,
simple `.class`/`#id`/`tag` rules apply (the `.ghost` fill and the brand-blue `.dot` are correct),
`clip-path`, gradients, and CSS paint values (`fill:url(#sea)` parses) — only the selector matching
and the animations are missing.

## 3. Scope decisions

In scope:

- **CSS stylesheet**: document-wide `<style>` registry in document order; simple, compound and
  descendant selectors; `*`; specificity and source order; `!important` priority.
- **CSS Animations**: `@keyframes` (multi-selector offsets, `from`/`to`, implicit endpoints from the
  base style); `animation` shorthand and longhands (duration, timing-function, delay,
  iteration-count, direction, fill-mode, play-state); comma-separated lists; animating `opacity`,
  `transform`, `fill` and `stroke`.
- **Timing functions**: `linear`, `ease*`, `cubic-bezier()`, `steps()`/`linear()` (sampled into
  keyframes when Core Animation cannot express them).
- **CSS transform semantics**: the `transform` property replaces the `transform` attribute; default
  `transform-box: view-box`, `transform-origin` with `fill-box`/percentages where it changes the
  rendered result (rotate/scale).
- **Media queries** for `prefers-color-scheme` and `prefers-reduced-motion`, with the appearance and
  Reduce Motion state plumbed through `SVGView`/`SVGRenderer`.
- **CSS `filter: drop-shadow()`** (the original uses it only in the dark variant).
- Tests, docs (`CONFORMANCE.md`, `CHANGELOG.md`, `MIGRATION.md` when public API grows), example demo.

Out of scope (documented as such, do not grow the scope silently): full CSS cascade (pseudo-classes,
attribute selectors, sibling combinators, `@supports`, custom properties, `@font-face`), CSS
transitions, and a complete SMIL engine.

**Invariant:** animated documents never enter the pixel corpus. The parity corpus keeps
`Example/Example/data` static-only (enforced by `CorpusLoader`); the animated demo files stay in the
gallery.

## 4. Milestones

### M1 — CSS stylesheet correctness (static appearance)

The original file stops rendering black: the waves get their gradient, `.wB` its light-blue, `.shine`
its glint, `.dot`/`.ghost` unchanged.

| # | Work item | Eng-days |
|---|---|---|
| 1 | Document-wide `<style>` registry in document order (replace ancestor-chain lookup; also parse `<style>` inside `<mask>/<pattern>/<clipPath>`) | 2–3.5 |
| 2 | Selector model: compound selectors, descendant combinator, `*`, specificity + source order (replaces the tag/class/id buckets) | 2.5–4.5 |
| 3 | Tests (selector matrix, cascade order, CSS paint references from matched rules) + docs | 1.5–2.5 |

**Acceptance:** a static 256×256 raster of the original matches a WebKit snapshot of the same file
within the parity tolerance (the animation's base state, i.e. what CoreSVG draws); the Example
gallery shows the blue wordmark. Corpus parity counts unchanged (no corpus file uses these
constructs — measured).

### M2 — CSS Animations core (the original moves)

| # | Work item | Eng-days |
|---|---|---|
| 1 | Validation spike: past-`beginTime` attach on the deferred path, per-segment `timingFunctions`, `repeatCount` semantics, control points | 0.5–1 |
| 2 | `@keyframes` parser + document registry (percentage lists, `from`/`to`, last-name-wins, limits) | 1–2.5 |
| 3 | `animation`/`animation-*` model: non-inherited carrier resolved through the cascade, comma lists, delays, direction, fill-mode, play-state | 2–4 |
| 4 | Timing functions → `CAMediaTimingFunction`/sampled keyframes | 0.75–1.5 |
| 5 | Keyframes → per-property `CAAnimation` builder: implicit endpoints from captured base values, per-segment timing, repeat/direction/fill, namespaced keys, SMIL coexistence | 2–4.5 |
| 6 | Integration with `SVGView`'s deferred attach (same "attach on main once windowed" path; epoch preserved on re-render) | 1–2 |
| 7 | Tests: parser/cascade/builder/trajectory (no presentation-layer asserts on CI) + docs | 1.5–3 |

**Acceptance:** the original animates like the browser — intro rise ~1.95 s, wave scroll 2.4/3.6 s
loops, five staggered bubbles, 6 s shine sweep, dot hop from 2 s; no restart on resize/rotation; a
frame-by-frame comparison with WebKit (harness in M4) is within tolerance at the sample times
`t = 0.25, 1.0, 2.0, 4.5, 6.2 s`.

### M3 — media queries, appearance, transform-origin, drop-shadow

| # | Work item | Eng-days |
|---|---|---|
| 1 | `@media` parse/evaluate + appearance plumbing (`SVGView` trait change → re-render) + Reduce Motion config | 3.75–6.5 |
| 2 | `!important` priority (needed by the reduced-motion rule) | 1–1.75 |
| 3 | CSS `transform` + `transform-box`/`transform-origin` (rotate/scale keyframes; `fill-box` needs a content bbox) | 3–4.5 |
| 4 | Reduce Motion end-to-end (public knob, CHANGELOG/MIGRATION) | 0.5–1 |
| 5 | CSS `filter: drop-shadow()` | 1.25–2 |

**Acceptance:** on the Example "Dark" backdrop the dark palette from `@media (prefers-color-scheme:
dark)` applies (`.sea-g` glow included); with Reduce Motion on, infinite animations stop; the
original's light-mode look is unaffected.

### M4 — verification harness, gates, docs

| # | Work item | Eng-days |
|---|---|---|
| 1 | Animation-frame oracle: Example app seeks `document.getAnimations()` to `currentTime = t` in WKWebView and snapshots; the kit raster uses `shapeLayer.speed = 0; timeOffset = t`. Small dedicated fixture set (NOT the parity corpus); report-only at first | 1.5–3.5 |
| 2 | Gate strategy: trajectory tests as the CI gate; frame oracle run-on-demand; docs, CHANGELOG, MIGRATION | 1.5–3 |

## 5. Test strategy

- **Unit/trajectory tests** (CI gate): parse, cascade, built `CAAnimation` fields (`values`,
  `keyTimes`, `timingFunctions`, `duration`, `repeatCount`, `fillMode`, `beginTime`), easing sampled
  as pure math, epoch/re-render semantics — the pattern of the existing `SVGAnimationTests`/
  `SVGAnimationTrajectoryTests`. Never assert presentation-layer state on headless CI.
- **Frame oracle** (on demand, from the Example app, like the WebKit parity dump): seek the browser
  animation and the CA timeline to the same `t` and compare rasters. This is the only honest answer
  to "does it look like the browser"; keep it out of the pixel corpus and out of the default gate
  until its determinism is measured.
- **Pixel corpus**: unchanged, static only. Add static CSS-selector fixtures to the corpus (they are
  comparable) once M1 lands; animated docs stay excluded by `CorpusLoader.hasRenderingAnimation`.
- **Manual/device checks** via Xcode MCP: the original icon in the Example gallery, resize/rotation,
  Reduce Motion on/off, dark substrate.

## 6. Risks and mitigations

| Risk | Mitigation |
|---|---|
| CSS cascade is a cliff: "just enough" rules grow into a spec project | Freeze the documented subset in `CONFORMANCE.md`; no pseudo-classes/attribute selectors/custom properties in v1 |
| CSS animation semantics vs Core Animation differ (per-property split, function lists vs matrix decomposition, alternate direction, play-state) | M2 spike first; split one CSS animation into one CA animation per property; sample where CA cannot express |
| Animations look right but are lost/accepted wrongly depending on when the layer is installed | Already solved by the deferred attach path; every new animation source must go through it |
| Pixel parity cannot judge animated output | Frame oracle + trajectory tests; never add animated fixtures to the corpus |
| `transform-box: fill-box` needs a per-element content bbox; interacts with viewBox scaling and mask/pattern resolution (B119-6) | Compute the bbox at build time in the element's user space; pin with targeted tests; keep `view-box` the default |
| Dark-mode/look changes re-render lists on appearance changes (cost) | Re-render only when the document actually used a relevant media query (a per-document flag); measure in the Example gallery |
| Public API grows (appearance, Reduce Motion) | Additive API only; CHANGELOG + MIGRATION entry, tests free of warnings |
| Performance regression for static documents | Gate CSS parsing/animation behind a "document has CSS animations" flag; static corpus must keep its current timings |

## 7. Estimates (one senior iOS engineer who knows the repo; 1 day ≈ 6 productive hours)

| Bundle | Eng-days (typical) |
|---|---|
| M1 — static CSS correctness | 6–10.5 (~8) |
| M2 — CSS Animations core (the original animates) | 9–19.5 (~13) |
| M3 — media/appearance, transform-origin, drop-shadow | 9.5–15.75 (~12) |
| M4 — frame oracle, gates, docs | 3–6.5 (~5) |
| **Total** | **27.5–52 (~38)** |

Cheaper options already available: the converted asset (0.5–1 day, done) and a build-time converter
(3–6 days) for teams that can preprocess assets — neither makes designer files work at runtime.

## 8. Suggested order

1. **M1** — largest visual gain per day; no animation semantics involved; the original stops being
   black. Ship as its own change (high confidence, parity-neutral).
2. **M2** — the feature the user actually asked for ("animation must play"). Spike first, then
   builder; ship behind the existing profile docs update.
3. **M3** — only if the product needs dark-mode assets / accessibility-driven motion; otherwise
   defer. Reduce Motion is the one item worth doing with M2 on accessibility grounds.
4. **M4** — the frame oracle early enough to validate M2 (build it in parallel with M2, not after).

## 9. Definition of done (for the original file)

- [ ] `SVGView` + original file: blue gradient wordmark, ghost R, brand-blue dot (no black shapes).
- [ ] Motion matches WebKit on the sample frames within tolerance; no visible flicker or restart on
      resize/rotation; the converted copy still works.
- [ ] Animated documents remain excluded from the pixel corpus; static CSS-selector fixtures added and
      triaged; both parity baselines unchanged.
- [ ] `CONFORMANCE.md` documents the CSS selector and CSS Animations subsets and their divergences;
      `CHANGELOG.md`/`MIGRATION.md` updated; tests cover parser, cascade, builder and trajectory.
- [ ] Example gallery: original and converted copy side by side; Reduce Motion honoured.
