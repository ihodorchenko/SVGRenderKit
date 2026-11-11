# Plan: resource limits, memory budgets, cancellation and cross-thread safety

Status: **planned — none of the new work below has started**. It records the open questions and the
verification checklist of the last robustness review so they can be worked item by item. It extends
the work of B102 (caps on untrusted input), B112 (render cancellation), B114 (colour overrides drop
the cache) and B133 (cache generation, memory accounting). Code facts below are from commit
`4937352`; every number marked *to be measured* must come from a reproduction or a benchmark before
it is written into the plan or the code (see "Working on a bug" in CLAUDE.md).

## 1. Goal

Answer four questions with measurements instead of code-reading, then bound what is currently
unbounded:

1. **Is there a cap on the total number of shapes, path segments and intermediate layers?**
2. **Can a set of documents that each fits the limits exhaust memory collectively?**
3. **How quickly are cancelled/superseded tasks interrupted?**
4. **Is there a limit on the total processing time of one document?**

and pin the five cross-thread scenarios of §4 with tests. The public contract must stay the same:
normal icons render identically, parser caching keeps working, and untrusted input still degrades
gracefully instead of failing a whole document (B102 policy).

## 2. Current state (from the code, to be confirmed by measurement)

### 2.1 Caps that already exist (`SVGInputLimits`)

| Cap | Value | Bounds |
|---|---|---|
| `maxInputBytes` | 32 MiB | the source, checked before XML parsing |
| `maxNestingDepth` | 256 | container depth (parse, build, bounds) |
| `maxUseDepth` / `maxUseExpansions` | 10 / 8192 | `<use>` fan-out in one render pass |
| `maxHrefChainDepth` | 32 | gradient/pattern `href` chains |
| `maxPaintBitmapDimension` | 4096 px | one mask or pattern tile bitmap |
| `maxRenderDimension` | 8192 px | one `SVGRenderer` output side (throws) |
| `maxImagePixels` | 64 Mpx | one decoded embedded `<image>` |
| `maxBlurRadius` | 500 px | filter blur radius |

Not capped today: **number of elements/shapes per document, number of path commands per document,
number of layers, number of paint servers, retained cache bytes, concurrent raster bytes, total
render time**. The 32 MiB source limit bounds all of them only indirectly and extremely generously.

For scale: the tracked corpus (`Example/Example/data`, measured 2026-11-11 with a script over
`git ls-files`) has a maximum of **574 elements**, **16,065 path commands** and **248 KB** per
document (`folder_2/PASSPORT_33_gray.svg`). Caps an order of magnitude above these can be generous
and still protect the process; they must be verified against the corpus, not guessed.

### 2.2 Memory

- **Parser cache** (`SVGCache`): 100 trees, LRU by count, **no byte budget**. A tree may come from a
  32 MiB source; the object graph is typically larger than the source.
- **Per-document bitmap caches** (`SVGBoundedCache`): pattern tiles — 16 entries / 96 MiB **per
  pattern tag**; mask images — 16 / 96 MiB **per mask tag**; decoded `<image>` — 1 entry, **no byte
  budget**; fonts — 64 entries, global. The budgets are per cache instance, so a document with *k*
  patterns or masks can retain *k* × 96 MiB, and a cache entry larger than the whole budget is still
  stored alone (`SVGBoundedCache.set`).
- **Embedded images**: `maxImagePixels` 64 Mpx ⇒ one decoded RGBA bitmap up to ~256 MiB, cached per
  `<image>` tag; a 32 MiB source can carry several.
- **Rasterizer**: an output up to 8192×8192 (~256 MiB RGBA) times
  `max(2, activeProcessorCount)` concurrent operations in `SVGRenderer.rasterizeQueue`, plus encoder
  copies (PNG/JPEG). Per-render cap only, no global raster memory budget.
- A `resetCache()` during a parse is already handled: the parse snapshots the generation and a stale
  tree is not stored (B133 e).

**Theoretical retained worst case**: 100 documents × (tree + per-tag bitmap caches) — multi-GB. It
must be reproduced (M1) before choosing budgets, but the structure allows it.

### 2.3 Cancellation

- `SVGView` uses a supersede model, not `Task` cancellation: the main thread bumps `loadGeneration`
  and a thread-safe mirror lets queued work exit before parsing (`SVGView.load` guard). Checks exist
  (a) when the queued block starts, (b) before installing the built tree on main (success and
  failure paths). **There is no check while parsing or building**; a superseded view reuses the
  serial queue only after the current build finishes.
- `SVGRenderer` has a cooperative `CancelToken` (B112) checked (a) when the queued block starts,
  (b) after `prepare` (parse + layer build), (c) when the rasterize operation starts. Nothing checks
  *inside* `prepare` or during rasterization/encoding: a cancel during rasterization still completes
  with data.

So the honest current answer to question 3 is "at checkpoints only"; the latency numbers are
*to be measured* (M1). A queued-but-not-started job is abandoned almost immediately; a running
parse/build runs to completion; a running rasterize is not interrupted.

### 2.4 Cross-thread invariants that exist by construction

- `SVGWorkQueue.shared` is one serial `DispatchQueue` for parsing/layer building of both `SVGView`
  and `SVGRenderer`; rasterization and encoding use a separate bounded `OperationQueue`.
- `SVGOptions` is **shared mutable state on the cached root** (`appearance`, `reduceMotion`,
  `renderScale`, `usesPatterns`/`usesMasks`, `defersAnimationAttach`, `deferredAnimations`,
  `animationEpoch`). It is mutated per render; today this is safe only because every mutation happens
  on the serial work queue. This is the main reason the scenarios in §4 are worth pinning with tests
  rather than a code review.
- Layer trees, gradient layers and mask layers are created per build; the bitmap caches share
  immutable `CGImage`/`UIImage` values behind locks; `SVGConfiguration` serializes its dictionaries
  through a concurrent queue with barriers.

## 3. Open questions

Each question is closed by a measurement recorded in this document, plus the work item that makes
the answer "bounded" rather than "not today".

### Q1 — total shapes, path segments, intermediate layers

**Current answer: not limited.** Only the 32 MiB source, the 256-depth nesting and the `<use>`
expansion budget bound the work; a small source can contain hundreds of thousands of elements, and a
single `d` attribute can contain millions of commands. **Work item M2**: a per-render work budget
(elements visited, path commands, layers created) in `SVGInputLimits` style, with degradation: skip
the excess and log, as B102 does. **Exit criterion**: a document above the cap builds in bounded
time/memory and degrades; the corpus (max 574 elements / 16,065 commands) and both parity gates are
unaffected.

### Q2 — collective memory across documents

**Current answer: yes, in principle.** The parser cache is bounded by entry count, not bytes, and
the bitmap budgets are per tag instance, not global (§2.2). **Work item M3**: a byte cost for the
parser cache and one global budget shared by all paint caches (or per-document budgets with a global
ceiling), plus a decode budget for `<image>`. **Exit criterion**: a reproduction with N documented
worst-case documents retains at most the configured budget; RSS in the Example app stays flat while
scrolling the gallery; cache hit rate does not collapse (measured).

### Q3 — cancellation latency

**Current answer: at checkpoints only** (§2.3). **Work item M4**: measure the three cases (queued,
mid-build, mid-raster) and decide whether the guarantee is "abandoned before parse" plus a work-budget
checkpoint, or a stricter one; add the missing checkpoint(s) and define what a cancelled
`SVGRenderer` render returns (today a cancel during rasterization can still return data).

**Exit criterion**: the measured worst-case latency is documented here and pinned by a test with a
deterministic barrier (not a sleep); rapid `SVGView` reuse never installs a stale tree or stale
animations.

### Q4 — total processing time of one document

**Current answer: no limit.** Only structural caps exist; a pathological document that fits them can
take an arbitrary amount of time (path parsing, layer building, masks/patterns). **Work item M2**:
a deterministic work/step budget for the render (not a wall-clock timeout, so CI is reproducible),
and optionally a deadline as a backstop in the untrusted-input path. **Exit criterion**: a
"slow but valid" fixture (e.g. one huge `d`, or many mask references) is cut at the budget with a
log and bounded time; real documents and the corpus are untouched.

## 4. Verification matrix (the reviewer's checklist)

These are the five scenarios to pin; names are proposed and follow the existing test naming.
"Existing" means extend the named test rather than duplicate it.

| # | Scenario | Test | Pass criterion |
|---|---|---|---|
| C1 | One SVG rendered concurrently by several tasks | `SVGConcurrencyTests.testOneDocumentRenderedByManyTasksIsDeterministic` (extend `SVGRendererTests.testConcurrentRendersMatchSequentialRenders`) | every result is byte-identical to the sequential render; no crash, no cross-talk in `SVGOptions` |
| C2 | The same cached tree rendered with different per-element overrides (`overrideElements`, fill/stroke colours) | `SVGConcurrencyTests.testCachedTreeWithDifferentOverridesDoesNotCrossContaminate` | each render equals its own sequential baseline; a different override set changes only its own output; the cached tree is not mutated |
| C3 | Configuration change and cache reset in parallel with renders | `SVGConcurrencyTests.testConfigurationChangeAndResetDuringConcurrentRenders` (extend `SVGRobustnessTests.testCacheResetIsThreadSafe`, `SVGViewLifecycleTests.testCacheFlagAndResetAreSafeUnderConcurrency`) | no crash/race; a render is either fully old-state or fully new-state, never mixed; stale parses are dropped (B133 e) |
| C4 | Cancellation on fast reuse of `SVGView` | `SVGViewLifecycleTests.testRapidReuseAbandonsSupersededLoad` (extend `testSupersededQueuedLoadsLeaveLatestSource`) + a latency assertion from M1 | the last source wins; no stale layer tree, parser or deferred animation is installed; superseded work stops before parsing or at the next budget checkpoint |
| C5 | No mutation of shared `CALayer`s/gradient objects after hand-off between queues | `SVGConcurrencyTests.testRepeatedBuildsShareNoMutableLayerObjects` | two builds of the same cached root return disjoint layer graphs; the second build leaves the first tree's geometry/colours/animations unchanged; shared bitmap caches are immutable values |

C1–C5 should also run with the thread sanitizer once locally (and optionally as a separate CI job);
the default suite stays fast. Use explicit barriers/`DispatchGroup`/continuations, never sleeps, so
the tests are not flaky on a loaded runner.

## 5. Work breakdown

Estimates are rough and assume one engineer who knows the repo.

### M1 — Measure and reproduce (0.5–1 day)

- Build the adversarial fixtures *within current limits*: many elements, a huge `d`, many masks and
  patterns, many distinct documents to fill the parser cache, a max-size raster.
- Measure: parse/build time and peak RSS; retained bytes after N documents; cancellation latency for
  queued / mid-build / mid-raster; raster memory with `max(2, cores)` concurrent max-size outputs.
- Record the numbers in this document (replacing "to be measured") and turn each finding into a red
  test before fixing (CLAUDE.md rule).

### M2 — Work budgets (2–3 days)

- Extend `SVGInputLimits` with per-render counters: elements/shapes, path commands, layers, paint
  server renders. Keep them thread-local (same pattern as the existing counters, reset in
  `beginRender`).
- Check the budget in the hot walks (`appendChildLayers`, path parsing, mask/pattern/marker
  rendering) every N items; on overflow skip the excess and log once, not per element.
- Add an optional deterministic step/time backstop for the `SVGView`/`SVGRenderer` path; decide the
  semantics for `SVGRenderer` (degrade vs throw) in §6.
- Provisional targets (to confirm in M1, must be far above the corpus maxima 574 / 16,065 / 248 KB):
  e.g. 16k elements, 1M path commands, 16k layers per document.

### M3 — Memory budgets (2–3 days)

- Give `SVGCache` a byte cost (measured tree bytes or source-bytes × factor) and a global byte
  budget in addition to `maxCount`; keep the LRU recency and the generation guard.
- Replace per-instance paint budgets with a shared byte budget (pattern tiles + mask bitmaps +
  decoded images) or add a global ceiling that accounts for every instance; keep the
  clear-on-overflow policy or make it configurable.
- Bound decoded `<image>` memory (the `1` entry / no-cost cache today) and reconsider
  `maxImagePixels` (64 Mpx ≈ 256 MiB RGBA) against real assets.
- Account for rasterization: a semaphore or byte budget for concurrent max-size outputs, so
  `rasterizeQueue.maxConcurrentOperationCount` cannot multiply a 256 MiB bitmap by the core count.
- Tests: accounting tests in `SVGCacheBudgetTests` style (deterministic, no RSS assertions); one
  manual/Example RSS measurement for the real-world claim.

### M4 — Cancellation (1.5–3 days)

- `SVGView`: check the generation mirror at the M2 budget checkpoints while building, so a superseded
  load stops between chunks instead of after a full build. Never install a partial tree.
- `SVGRenderer`: check the token inside `prepare` at the same checkpoints; decide and implement the
  "cancel during rasterize" result (check the token before encoding, at least after rasterization).
- Tests: queued cancellation (exists), mid-build cancellation (new, with a large fixture and a
  deterministic hook/barrier), `SVGView` rapid reuse (C4), latency assertion recorded in M1.

### M5 — Cross-thread invariants (1.5–2.5 days)

- Implement C1–C5 from §4; add the new file `SVGConcurrencyTests.swift`.
- Audit for shared mutable objects handed between queues: `SVGOptions` fields, deferred animations,
  `SVGBaseGradient.stops`/`transform` (immutable after parse?), cached `CGImage`/`UIImage` values.
  Make the invariant explicit in comments where it is only "true because of the serial queue".
- If a race is found, the minimal fix plus a regression test; TSan locally, optional CI job.

### M6 — Docs, gates (0.5–1 day)

- README: document the limits and the cancellation guarantees (currently only B102's list is
  described loosely).
- CHANGELOG `Unreleased`: user-visible behaviour changes only (a document that used to render may
  now degrade, if a cap is hit; a cancelled render may throw earlier).
- MIGRATION only if the public contract changes (it should not: limits stay internal).
- Gates: full suite, corpus parity (CoreSVG + WebKit) unchanged, `perf.json` gate green. The budget
  checks must not show up in the perf baseline (measure; per-N checks should be negligible).

## 6. Decisions needed before implementation

1. **Degrade vs throw at a budget cap.** B102's policy is skip + log for untrusted input, throw only
   for caller-controlled output (size, scale). Keep that split: a document over an element/path cap
   degrades; `SVGRenderer` throws only where the caller can react.
2. **Budget units.** Deterministic work units (elements, commands, layers) are preferred over wall
   clock so tests and CI are reproducible; a deadline may exist only as a last-resort backstop for
   the untrusted path, and must be documented as non-deterministic.
3. **Memory scope.** Global byte budgets (process-wide) vs per-document: a global budget is the only
   honest answer to Q2, but it can evict hot data across independent screens; measure hit rate.
4. **Cancellation semantics.** Define what `SVGRenderer` returns when cancellation arrives after the
   build but during rasterization (probably `CancellationError`, checked before encoding), and what
   `SVGView` guarantees (superseded load abandoned; no partial install).
5. **Public API.** Keep the limits internal like `SVGInputLimits` unless a client needs to tune them;
   if a knob is added, it is additive and gets a CHANGELOG/MIGRATION entry.

## 7. Acceptance criteria

- Q1–Q4 are answered in this document with measured numbers and a test that fails before the fix.
- Element/path/layer budget enforced with the B102 degradation policy; the tracked corpus is
  unaffected (parity counts unchanged, no `PARITY_SKIP`/`CORPUS_FAIL` movement).
- Parser and paint caches respect byte budgets; a worst-case set of documents stays within the
  configured ceiling (measured, not estimated); gallery scrolling RSS is flat.
- Cancelled/superseded work stops at a defined checkpoint; the measured worst-case latency is
  documented and pinned by a test.
- C1–C5 green, thread-sanitizer clean locally, no flaky tests (no sleeps, no timing assumptions
  beyond a generous ceiling).
- Full suite, both parity gates and the perf gate green; README/CHANGELOG updated.

## 8. Risks

| Risk | Mitigation |
|---|---|
| A cap hides a legitimate complex document | Set caps from measured corpus maxima with a wide margin; degrade with a log; a single-document cap, not a global one |
| Budget checks cost time or break parity | Check every N items (amortised), measure Release A/B against the perf baseline, parity gates unchanged |
| Global memory budgets evict hot documents and hurt hit rate | Measure hit rate and gallery scrolling; keep recency; make the budget generous enough for common lists |
| Cancellation during the build leaves partial state | Only discard the result; installation on main is all-or-nothing; keep the existing generation checks at install |
| Concurrency tests are flaky on CI | Deterministic barriers, no sleeps, one shared serial queue already serialises the risky section; TSan job informational |
| RSS/limit tests are environment-dependent | Assert accounting counters in tests; keep RSS as a manual/Example measurement recorded in this doc |
| The plan drifts into sandboxing/OS-level limits | Explicitly out of scope (§9); this is about bounding this library's own work and caches |

## 9. Out of scope

Process/thread sandboxing, watchdog kills of runaway work, preemptive timeouts, per-document process
isolation, network/external resources, and public configuration of every limit. Those are a different
product decision.

## References

- Caps and degradation: `Sources/SVGRenderKit/SVGInputLimits.swift`, B102.
- Cache and generation: `Sources/SVGRenderKit/SVGCache.swift`, `SVGBoundedCache.swift`,
  `SVGConfiguration.swift`, B114/B133.
- Cancellation: `Sources/SVGRenderKit/SVGRenderer.swift` (`CancelToken`), `SVGView.swift`
  (`loadGeneration`/`latestGeneration`), B112.
- Shared per-render state: `SVGOptions` in `SVGElement.swift`, `SVGView.load`, `SVGRenderer.prepare`.
- Existing tests to extend: `SVGRendererTests`, `SVGCacheEvictionTests`, `SVGCacheBudgetTests`,
  `SVGInputLimitsTests`, `SVGMemoryManagementTests`, `SVGViewLifecycleTests`, `SVGRobustnessTests`,
  `SVGPerformanceTests`.
