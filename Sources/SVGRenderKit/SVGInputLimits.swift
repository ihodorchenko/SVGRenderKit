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

    /// Maximum side (in px) of a mask or pattern bitmap. A larger region degrades to
    /// no mask / no pattern rather than allocating a huge image.
    static let maxPaintBitmapDimension: CGFloat = 4096

    /// Maximum side (in px, after `scale`) of an `SVGRenderer` output bitmap. The
    /// renderer throws here, because the caller picks the size and can react.
    static let maxRenderDimension: CGFloat = 8192

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
