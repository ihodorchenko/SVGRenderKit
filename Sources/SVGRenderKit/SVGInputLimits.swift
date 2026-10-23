import UIKit

/// Caps on the work a single document may trigger, so untrusted input cannot hang
/// the parser or exhaust memory (B102). Past a cap the library degrades gracefully —
/// it skips the excess and logs — instead of failing the whole document.
///
/// The counters are per-thread: a cached tree may be rendered on several threads at
/// once, and parsing/building for a given render stays on one thread.
enum SVGInputLimits {

    /// Maximum nesting depth of container elements. Children below the cap are
    /// dropped, so a pathological document cannot overflow the stack while parsing,
    /// building layers, or computing bounds.
    static let maxNestingDepth = 256

    /// Maximum number of `<use>` expansions in one render pass. A chain of references
    /// that fans out (`<g id="b"><use href="#a"/><use href="#a"/></g>` …) is a DAG, not
    /// a cycle, so the cycle guard alone would still expand it to 2ⁿ layers.
    static let maxUseExpansions = 8192

    /// Maximum nesting depth of `<use>` expansions. Together with the expansion budget
    /// this bounds a fan-out chain (`<use>` → group → `<use>` …) that would otherwise
    /// produce 2ⁿ layers; real icons nest a couple of levels at most.
    static let maxUseDepth = 10

    /// Maximum length of an `xlink:href` inheritance chain (`<linearGradient href>` → …,
    /// `<pattern href>` → …). `resolveHref()` recurses once per link, so an unbounded chain would
    /// overflow the stack (the work queue's threads have a small stack: a Debug frame of
    /// `SVGPattern.resolveHref` already overflowed it at ~260 links); real documents chain two or
    /// three levels. Links past the cap are not
    /// followed.
    static let maxHrefChainDepth = 32

    /// Maximum side (in px) of a mask or pattern bitmap. A larger region degrades to
    /// no mask / no pattern rather than allocating a huge image.
    static let maxPaintBitmapDimension: CGFloat = 4096

    /// Maximum side (in px, after `scale`) of an `SVGRenderer` output bitmap. The
    /// renderer throws here, because the caller picks the size and can react.
    static let maxRenderDimension: CGFloat = 8192

    /// Maximum size of an SVG source in bytes; a larger document is rejected with a
    /// `SVGError.content` before it is XML-parsed.
    static let maxInputBytes = 32 * 1024 * 1024

    /// Maximum pixel count (width × height) of an embedded `<image>`; a larger bitmap is
    /// not decoded and the image is skipped.
    static let maxImagePixels = 64_000_000

    /// Cap on a blur radius in bitmap pixels; the cost of the blur grows with it.
    static let maxBlurRadius: CGFloat = 500

    /// A bitmap with these pixel dimensions fits within `limit` on both sides.
    static func bitmapFits(width: CGFloat, height: CGFloat, limit: CGFloat) -> Bool {
        width <= limit && height <= limit
    }

    // MARK: - Per-thread state

    private final class State {
        var nestingDepth = 0
        var boundsStack: Set<ObjectIdentifier> = []
        var activeUses: Set<ObjectIdentifier> = []
        var useExpansions = 0
        var activePatterns: Set<ObjectIdentifier> = []
        var hrefChainDepth = 0
    }

    private static let stateKey = "SVGRenderKit.SVGInputLimits.state"

    private static var state: State {
        let dict = Thread.current.threadDictionary
        if let existing = dict[stateKey] as? State { return existing }
        let created = State()
        dict[stateKey] = created
        return created
    }

    // MARK: - Nesting depth

    /// Enters a container while parsing. Returns `false` once the depth cap is reached,
    /// so the caller stops descending instead of overflowing the stack.
    static func enterContainer() -> Bool {
        let current = state
        guard current.nestingDepth < maxNestingDepth else { return false }
        current.nestingDepth += 1
        return true
    }

    static func exitContainer() {
        state.nestingDepth -= 1
    }

    // MARK: - contentBounds recursion

    /// Enters a group's `contentBounds` walk. Returns `false` when the group is already
    /// being measured (a `<use>` chain that closes on itself), so the walk stops.
    static func enterBounds(_ object: ObjectIdentifier) -> Bool {
        let current = state
        guard !current.boundsStack.contains(object) else { return false }
        current.boundsStack.insert(object)
        return true
    }

    static func exitBounds(_ object: ObjectIdentifier) {
        state.boundsStack.remove(object)
    }

    // MARK: - pattern tiles

    /// Enters a pattern's tile rendering. Returns `false` when this pattern is already
    /// being rendered further up the stack (its content paints with itself, directly or
    /// through other patterns), so the tile is skipped instead of recursing forever (B125).
    static func enterPattern(_ object: ObjectIdentifier) -> Bool {
        state.activePatterns.insert(object).inserted
    }

    static func exitPattern(_ object: ObjectIdentifier) {
        state.activePatterns.remove(object)
    }

    // MARK: - href chains

    /// Enters one link of an `xlink:href` inheritance chain. Returns `false` past
    /// `maxHrefChainDepth`, so the caller stops following the chain instead of overflowing
    /// the stack. Pair every `true` with `exitHref()`.
    static func enterHref() -> Bool {
        let current = state
        guard current.hrefChainDepth < maxHrefChainDepth else { return false }
        current.hrefChainDepth += 1
        return true
    }

    static func exitHref() {
        state.hrefChainDepth -= 1
    }

    // MARK: - <use> expansion

    enum UseAdmission {
        /// The expansion may proceed.
        case ok
        /// The `<use>` is already being expanded (a reference cycle).
        case cycle
        /// The `<use>` is nested deeper than `maxUseDepth`.
        case tooDeep
        /// The render pass has spent its expansion budget.
        case overBudget
    }

    /// Starts a render pass, resetting the `<use>` budget. A referenced root `<svg>`
    /// reached from within a `<use>` must not reset it, so the reset is skipped while an
    /// expansion is active.
    static func beginRender() {
        let current = state
        guard current.activeUses.isEmpty else { return }
        current.useExpansions = 0
    }

    static func enterUse(_ object: ObjectIdentifier) -> UseAdmission {
        let current = state
        if current.activeUses.contains(object) { return .cycle }
        if current.activeUses.count >= maxUseDepth { return .tooDeep }
        if current.useExpansions >= maxUseExpansions { return .overBudget }
        current.activeUses.insert(object)
        current.useExpansions += 1
        return .ok
    }

    static func exitUse(_ object: ObjectIdentifier) {
        state.activeUses.remove(object)
    }

    /// `<use>` expansions spent in the current pass on this thread (for tests).
    static var useExpansionsSpent: Int { state.useExpansions }
}
