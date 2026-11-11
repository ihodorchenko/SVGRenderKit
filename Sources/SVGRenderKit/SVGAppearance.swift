import UIKit

/// The appearance a document is resolved for: CSS `@media (prefers-color-scheme: …)`.
public enum SVGAppearance: Sendable, Equatable {
    case light
    case dark
}

/// How the runtime evaluates `@media (prefers-reduced-motion: reduce)`.
///
/// `.system` follows `UIAccessibility.isReduceMotionEnabled`, `.reduce` treats Reduce Motion as
/// enabled (a document that asks for it renders its reduced-motion variant) and `.allow` treats it
/// as disabled, which is useful for a preview or a screenshot tool that wants the full motion.
public enum SVGMotionPreference: Sendable, Equatable {
    case system
    case reduce
    case allow

    /// Whether the reduced-motion media query is in effect. `UIAccessibility` is main-actor
    /// isolated, so this is read from the view on the main thread.
    @MainActor
    var reducesMotion: Bool {
        switch self {
        case .system: return UIAccessibility.isReduceMotionEnabled
        case .reduce: return true
        case .allow: return false
        }
    }
}

/// The media-query inputs of one render: the resolved appearance and Reduce Motion state.
struct SVGMediaContext {
    let appearance: SVGAppearance
    let reduceMotion: Bool
}
