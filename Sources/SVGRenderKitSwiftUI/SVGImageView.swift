import UIKit
import SwiftUI
import SVGRenderKit

/// A SwiftUI view that renders an SVG document with `SVGView`.
///
/// The SVG keeps its aspect ratio and is centered inside the view's bounds (according to its
/// `preserveAspectRatio`). Like `Shape`, the view takes all the space it is offered, so give it a size:
///
/// ```swift
/// SVGImageView(name: "icons/my-icon.svg")
///     .frame(width: 48, height: 48)
/// ```
///
/// The document is re-parsed only when the source or the overrides actually change, not on every
/// SwiftUI redraw.
public struct SVGImageView: UIViewRepresentable {

    /// Where the document comes from; the equality drives reloading in `updateUIView`.
    fileprivate enum Source: Equatable {
        case resource(name: String, bundle: URL?)
        case string(String, name: String?)
        case data(Data, name: String?)
        case url(URL)
    }

    private let source: Source
    private let fillColors: [String: UIColor]?
    private let overrideElements: [String: SVGSourceStyleElement]?

    /// Renders the bundled SVG resource with the given name.
    /// - parameter name: The name of the SVG resource.
    /// - parameter bundle: The bundle containing the resource; `nil` means `Bundle.main`.
    /// - parameter fillColors: Fill colors to override, keyed by SVG element name.
    public init(name: String, bundle: Bundle? = nil, fillColors: [String: UIColor]? = nil) {
        self.source = .resource(name: name, bundle: bundle?.bundleURL)
        self.fillColors = fillColors
        self.overrideElements = nil
    }

    /// Renders the bundled SVG resource with the given name, overriding the style of specific elements.
    ///
    /// `SVGSourceStyleElement` is a reference type, so the document reloads when a different instance
    /// is passed for an element; keep the instances in state rather than recreating them in `body`.
    public init(name: String, bundle: Bundle? = nil, overrideElements: [String: SVGSourceStyleElement]) {
        self.source = .resource(name: name, bundle: bundle?.bundleURL)
        self.fillColors = nil
        self.overrideElements = overrideElements
    }

    /// Renders the given SVG markup.
    /// - parameter svgString: The raw SVG markup.
    /// - parameter name: An optional identifier used for parser caching.
    /// - parameter fillColors: Fill colors to override, keyed by SVG element name.
    public init(svgString: String, name: String? = nil, fillColors: [String: UIColor]? = nil) {
        self.source = .string(svgString, name: name)
        self.fillColors = fillColors
        self.overrideElements = nil
    }

    /// Renders the given SVG data.
    /// - parameter svgData: The raw SVG data.
    /// - parameter name: An optional identifier used for parser caching.
    /// - parameter fillColors: Fill colors to override, keyed by SVG element name.
    public init(svgData: Data, name: String? = nil, fillColors: [String: UIColor]? = nil) {
        self.source = .data(svgData, name: name)
        self.fillColors = fillColors
        self.overrideElements = nil
    }

    /// Renders the SVG file at the given URL (re-parsed when the file changes).
    /// - parameter svgURL: The file URL of the SVG.
    /// - parameter fillColors: Fill colors to override, keyed by SVG element name.
    public init(svgURL: URL, fillColors: [String: UIColor]? = nil) {
        self.source = .url(svgURL)
        self.fillColors = fillColors
        self.overrideElements = nil
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeUIView(context: Context) -> SVGView {
        let view = SVGView()
        // No intrinsic size: let SwiftUI decide, and never let the content push the layout.
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        // The SVG is decorative content by default; callers can use `.accessibilityLabel(_:)`.
        view.isAccessibilityElement = false
        return view
    }

    public func updateUIView(_ view: SVGView, context: Context) {
        let coordinator = context.coordinator
        let overrides = resolvedOverrides()
        guard coordinator.needsLoad(source: source, fillColors: fillColors, overrides: overrideElements) else { return }
        coordinator.record(source: source, fillColors: fillColors, overrides: overrideElements)

        switch source {
        case .resource(let name, let bundleURL):
            view.set(SVGName: name, bundle: bundleURL.flatMap(Bundle.init(url:)), overrideElements: overrides)
        case .string(let string, let name):
            view.set(svgString: string, name: name, overrideElements: overrides)
        case .data(let data, let name):
            view.set(svgData: data, name: name, overrideElements: overrides)
        case .url(let url):
            view.set(svgURL: url, overrideElements: overrides)
        }
    }

    /// Converts `fillColors` into the style-override representation `SVGView` expects.
    private func resolvedOverrides() -> [String: SVGSourceStyleElement]? {
        if let overrideElements { return overrideElements }
        guard let fillColors else { return nil }
        return fillColors.mapValues { SVGSourceStyleElement(fill: $0, stroke: nil, strokeWidth: nil) }
    }

    /// Remembers what the view was last loaded with, so redraws that change nothing do not reload it.
    public final class Coordinator {
        private var loaded: (source: Source, fillColors: [String: UIColor]?, overrides: [String: SVGSourceStyleElement]?)?

        fileprivate func needsLoad(source: Source, fillColors: [String: UIColor]?, overrides: [String: SVGSourceStyleElement]?) -> Bool {
            guard let loaded else { return true }
            return loaded.source != source
                || loaded.fillColors != fillColors
                || !Self.sameInstances(loaded.overrides, overrides)
        }

        fileprivate func record(source: Source, fillColors: [String: UIColor]?, overrides: [String: SVGSourceStyleElement]?) {
            loaded = (source, fillColors, overrides)
        }

        private static func sameInstances(_ lhs: [String: SVGSourceStyleElement]?, _ rhs: [String: SVGSourceStyleElement]?) -> Bool {
            switch (lhs, rhs) {
            case (nil, nil): return true
            case let (lhs?, rhs?):
                return lhs.count == rhs.count && lhs.allSatisfy { key, value in rhs[key] === value }
            default: return false
            }
        }
    }
}
