# SVGRenderKit — guide for agents and contributors

A Swift package (iOS): SVG → object tree → `CALayer`. The supported SVG profile and the policy on
deliberate divergences live in [CONFORMANCE.md](CONFORMANCE.md) (not duplicated here), the history in
[CHANGELOG.md](CHANGELOG.md), migrations in [MIGRATION.md](MIGRATION.md). Code, comments, docs and
commit messages are in English.

## Tests

- **Never run the tests synchronously in the main thread/dialog** — it blocks the session. Run them
  through a subagent or in the background and only poll the status now and then. The subagent returns a
  short summary: the number of tests, the list of failures, the crash lines.
- Command: `Scripts/run-tests.sh` — a wrapper over `xcodebuild test`. After the result line `xcodebuild`
  often does not exit on its own (Xcode 26/27), so the script waits for the result line, kills the
  hung process and parses the log itself. The verdict (last line, also in `$LOG.verdict`) is one of
  `PASSED`, `WARNINGS`, `FAILED`, `BUILD-FAILED`, `CRASHED`, `HUNG` (the log has not grown for more
  than `STALL_SECONDS`, 180 s), `NO-RESULT`. The exit code is 0 only for `PASSED`.
- The Debug benchmarks (`SVGPerformanceTests`) are skipped by default; `PERF=1` runs them (they are not
  representative in Debug, see Performance).
- Arguments are passed through to `xcodebuild`: `Scripts/run-tests.sh -only-testing:SVGRenderKitTests/SVGMemoryManagementTests`.
  Variables: `LOG`, `DESTINATION` (default `platform=iOS Simulator,name=iPhone 17`), `SCHEME`
  (`SVGRenderKit-Package`), `CLEAN=1`.
- Without the script: `xcodebuild test -scheme SVGRenderKit-Package -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SVGRenderKitTests`.
- **Do not run several test runs in parallel** (including from different worktrees on the same
  simulator): `xcodebuild` crashes/restarts and the test count comes out too low.
- An incremental build sometimes leaves the test bundle with stale objects: tests that are clearly fine
  fail (`SVGStylesTests.testStrokeLinecapParsed` — `nil` instead of a value). `CLEAN=1` fixes it; do not
  look for a bug in the code until you have rebuilt from scratch.
- The `Executed N tests` line in the `xcodebuild` log is sometimes incomplete after a crash — do not
  treat it as the test count; look at the script's verdict and at `CRASHED`/`HUNG`.

## Parity with the references

The corpus of real icons (`Example/Example/data`) is rendered by `SVGView` and compared pixel by pixel
with two oracles; the test is `SVGRenderParityTests.testCorpusParity`.

- **CoreSVG** (on every run by default): the `CORPUS_SUMMARY` line. Gate: `Scripts/check-parity.sh <log> .github/parity-baseline.txt`.
- **Browser (WKWebView/WebKit)**: the `WEBKIT_SUMMARY` line. WebKit does not start inside the test bundle
  (no `com.apple.developer.web-browser-engine.*` entitlement), so the Example app dumps the rasters
  (`WebKitParityRunner`) and the test reads them. One run of both oracles is `Scripts/webkit-parity.sh`
  (build → install → launch → tests → both gates; `SKIP_DUMP=1`, `SKIP_TESTS=1`, `RASTERS=…`).
  Gate: `.github/webkit-baseline.txt` (`check-parity.sh … WEBKIT_SUMMARY`). In CI it runs from `webkit-parity.yml`
  (nightly, manually, or on a PR with the `webkit` label).
- **Per fixture**: `check-parity.sh` only sees counts, so `Scripts/check-fixtures.sh <log> .github/parity-fixtures.txt`
  (CoreSVG, `CORPUS_FAIL`) and `.github/webkit-fixtures.txt` (`WEBKIT_FAIL`) keep the `differing` fraction of every
  failing fixture: a fixture that gets worse by more than `TOLERANCE` (0.01) or a new failing one fails the gate.
  The numbers of CI are the reference (all four CI jobs agree to three decimals; a local Xcode/OS can differ on a
  mask edge — `transaction_special.svg` is 0.154 locally, 0.175 on the runner), so take a baseline from a CI log.
  After an improvement or a triaged new fixture: `Scripts/check-fixtures.sh --update <log> <file> <PREFIX>`.
- A baseline file is a single summary line: `pass` must not drop, `fail`/`referenceLimited`/`webkitMissing`
  must not grow, `kitError` and `referenceMissing` are always 0. An improvement → update the baseline in
  the same commit; a regression → do not merge, fix it or triage it honestly in `ParityTriage` (a reason is
  mandatory).
- `reference-limited` — what CoreSVG cannot do (`display:none`, `<switch>`, 8-digit hex, stop mixing in a
  wide color space): our render is correct, there is no pixel gate.
- Untracked local folders under `Example/Example/data/*` inflate the corpus `total` locally — CI has a
  different `total`; compare with the baseline by `pass/fail`, not by `total`, and do not commit such folders.
- `.webkit-rasters` (a pointer to the dump) is in `.gitignore`, do not commit it.
- There are no radial gradients in the corpus; their fixtures are `referenceLimited` — targeted tests pin
  the geometry. CoreSVG and the kit interpolate color differently — this divergence is known.

## Performance

- Run only in Release: `-configuration Release ENABLE_TESTABILITY=YES` (Debug is not representative).
  Profile/measure first, change second — estimates "from the code" have been wrong twice already.
- `.github/perf-baseline.json` is taken **only from a CI runner** (the `perf.json` artifact of a green
  `perf.yml` run on main), never from a laptop.
- The `Scripts/perf_report.py` gate (parameters are in `perf.yml`): a test fails if it is slower than the
  baseline by more than 3×, the baseline is ≥ 50 ms and the absolute delta is ≥ 50 ms; tests with
  RSD > 35% (in the baseline or in the run) are only reported (`~`). On false positives raise
  `--fail-ratio`/`--min-seconds` instead of turning the gate off.
- Compare local numbers only crosswise: A/B/A/B in one session, `CPU Time`, the minimum over 10 iterations,
  plus a control that does not depend on the change (`svgViewCreateAndLayout50`). Single runs wander by
  ±35% and have produced false "regressions".
- Offscreen measurements do not describe the screen: `CAGradientLayer` is drawn by Core Animation, while any
  of our CG layers (`RadialGradientLayer`, masks, patterns) is rasterized in the app's display phase.
- Rough cost per shape relative to a plain fill: stroke ~1.2×, pattern ~1.3×, gradient ~6×, clip ~7×,
  mask ~10×, opacity ~12×. Parsing the corpus takes a fraction of a millisecond per icon.

## Working on a bug

1. First reproduce it with a minimal SVG/test — **red before the fix**. Items from reviewers/audits are
   estimates "from the code", not facts; close what cannot be reproduced as not-a-bug (with an invariant
   comment or a test if useful).
2. A minimal fix + a regression test; the relevant tests are green.
3. Parity no worse than the baseline for both oracles (see above).
4. A "spec/browser versus CoreSVG" divergence: follow the spec where the spec and the browser agree; keep
   CoreSVG's behavior only where it is clearly better on screen. The policy and the table of divergences
   are in CONFORMANCE.md.
5. A contract change (graceful degradation, public API) needs a CHANGELOG/MIGRATION entry and an explicit
   rename/strengthening of the affected tests (a test name must describe the real behavior).
6. Public API with typos is not removed in a minor release but kept as an `@available(*, deprecated, renamed:)`
   shim; a major release may break API (2.0 did), with a MIGRATION entry.

## Out of scope (when met, degrade: skip with a log, do not implement)

Scripts/DOM/events; external resources (`url(...)` over the network); `@font-face`/glyphs; `@media`;
interactive links (`<a>`); full SMIL (event `begin`, `additive`, `calcMode`, `fill="freeze"`); `textPath`,
per-glyph `x`/`y` lists; the CSS cascade (specificity, combinators, pseudo-classes; `inherit` only for
`visibility`, `clip-rule`, `fill-rule`, `text-anchor`); nested `<svg>`; `paint-order`,
`vector-effect`, `non-scaling-stroke`; `overflow`/`<view>`; font micro-properties, rendering hints;
`spreadMethod` `reflect`/`repeat` (rendered as `pad`); the relative units `ex`/`rem`/`ch`/`vw`/`vh`/
`vmin`/`vmax` (`em` is supported for `font-size`; on the root `em`/`auto` fall back to the `viewBox`); the
full filter pipeline (`feMorphology` etc.). If real icons start to need any of this, revisit it as a
separate decision (in particular `<a>` and a nested `<svg>` are currently dropped silently together with
their content).

## Decisions taken and rejected options

- **A linear gradient in sRGB was rejected.** Replacing `CAGradientLayer` with CG drawing that mixes in
  sRGB (as browsers do) came closer to the browser (browser fail 79→50), but it is noticeably slower on
  screen even with `drawsAsynchronously`, and `CAGradientLayer` matches CoreSVG. We stay on
  `CAGradientLayer`; do not propose it again without a way to measure the screen itself (see P28 below).
- **Won't-fix: the viewport clip of `<symbol>`** — it is `overflow`, which is out of scope.
- Clipping with the silhouette instead of a `mask` for a gradient is 33–42% faster but gives a different AA
  edge — 390 fixtures diverge from both oracles; do not do it.
- Narrowing the raster window of a `userSpaceOnUse` gradient to its bbox is up to 5× faster but shifts AA;
  kept in reserve in case it becomes the bottleneck.
- **The object model is internal (2.0).** Tags, `SVGRoot`, the container protocols and the vendored
  SWXMLHash are `internal`; the public surface is the views, `SVGRenderer`, `SVGCache`,
  `SVGConfiguration`, the style/paint/length value types and the helpers listed in MIGRATION.md.
  `SVGBaseGradient` stopped being an extension point: the parser instantiates concrete classes, so a
  third-party subclass could never be part of a parsed tree. `SVGView` stays `open`.
- `spreadMethod` pad-only and mixing the stops of a linear gradient "like CoreSVG" are deliberate
  divergences.

## Known open minor items and deferred work

Do these only on a user complaint or after a measurement.

- `<style>` is looked up along the ancestor chain, not across the whole document (needs a registry of
  rules in document order).
- `marker-mid`: arcs (`A`) can produce extra mid vertices; Bézier curves and subpaths already follow tangents.
- A gradient/pattern `stroke` on `<text>`/`<tspan>` is not supported (a solid stroke, opacity, clip, mask
  and filter are).
- `SVGCache.maxCount` is fixed (100); the tile/mask caches are limited by a byte budget.
- Performance: **P20** a cache of the `SVGRenderer` result/the `SVGView` raster for lists (changes the
  public API); **P25** parsing and layer building on a single serial queue, shared mutation of
  `options.renderScale`/`usesPatterns`; **P26** gradient/clip without an offscreen `mask` (a parity
  risk); **P27** walking the model straight into `CGContext`, a byte-level SAX instead of SWXMLHash;
  **P28** measuring on-screen drawing (the display phase of a live `SVGView`, dropped frames while
  scrolling the Example gallery); **P19/P21** caching `path.bounds`/resolved style, `SVGParseD` per segment.

## Pitfalls

- `style.display != .none` for an `SVGDisplaytype?` is silently read by the compiler as `!= nil` — unwrap
  first (`if let d = style.display, d == .none` / `switch`); only a compiler warning catches it.
- `parent` on tags is `unowned`: the invariant "a parent outlives its child" is held by the tree;
  violating it crashes. Do not keep a child/tag outside the tree without owning the root (there is a
  deinit test).
- Tests that go through `layer.animation`/`animation(forKey:)` are unreliable on headless CI; check the
  timeline epoch `SVGView.animationEpoch` and sample the trajectory.
- Unsupported units in `SVGLength.get` yield `.px(0)`: on the root `<svg>` that is 0×0 — there is a
  fallback to the `viewBox` there; account for it elsewhere.
- `SVGInputLimits` are thread-local limits on untrusted input (nesting 256, `<use>` depth 10 and 8192
  expansions, a mask/pattern bitmap of 4096 px, `SVGRenderer` throws above 8192 px, input 32 MB, an image
  of 64 Mpx, blur 500): exceeding one degrades (skip + log). New recursive walks (`contentBounds`,
  mask/pattern/clip/marker/filter references) must respect the guard against self-references.
- Masks/patterns/blur are rasterized at the output scale: a document must know what depends on the scale
  (`rendersScaledPaint`), otherwise it will not be redrawn on resize. The parity harness declares a 1×
  output through `SVGView.outputScale`.
- New public API with typos/renames goes only through a deprecated shim; keep the shim tests free of
  warnings.
- Tests that pin a bug (the old behavior) must be changed together with the fix, not worked around.
