import UIKit

/// Central, shared configuration for the renderer: parser caching, reload
/// notifications, and global color overrides.
public final class SVGConfiguration {
    /// The shared configuration instance.
    public static let shared = SVGConfiguration()

    /// Whether parsed SVG roots are cached. Defaults to `true`.
    public var isParserCacheEnabled: Bool = true

    /// The notification name that triggers cached SVG views to reload, or `nil` to disable.
    public var updateNotificationName: NSNotification.Name? {
        willSet {
            if let name = updateNotificationName {
                NotificationCenter.default.removeObserver(self, name: name, object: nil)
            }
        }
        didSet {
            if let name = updateNotificationName {
                NotificationCenter.default.addObserver(
                    self, selector: #selector(handleUpdateNotification), name: name, object: nil)
                SVGView.updateNotificationName = updateSvgImagesNotification
            } else {
                SVGView.updateNotificationName = nil
            }
        }
    }

    private let updateSvgImagesNotification = NSNotification.Name("SVGView_updateSvgImagesNSNotification")

    private let accessQueue = DispatchQueue(label: "SVG.Configuration", attributes: .concurrent)
    private var colorOverrides: [String: String] = [:]
    private var uiColorOverrides: [String: UIColor] = [:]

    private init() {}

    /// Adds name-to-color-string overrides that take precedence when resolving colors.
    func addColorOverrides(_ colors: [String: String]) {
        accessQueue.async(flags: .barrier) {
            for (key, value) in colors { self.colorOverrides[key] = value }
        }
    }

    /// Replaces all name-to-color-string overrides.
    func setColorOverrides(_ colors: [String: String]) {
        accessQueue.async(flags: .barrier) { self.colorOverrides = colors }
    }

    /// Adds name-to-`UIColor` overrides that take precedence when resolving colors.
    func addUIColorOverrides(_ colors: [String: UIColor]) {
        accessQueue.async(flags: .barrier) {
            for (key, value) in colors { self.uiColorOverrides[key] = value }
        }
    }

    /// Replaces all name-to-`UIColor` overrides.
    func setUIColorOverrides(_ colors: [String: UIColor]) {
        accessQueue.async(flags: .barrier) { self.uiColorOverrides = colors }
    }

    func colorOverride(byString key: String) -> String? {
        accessQueue.sync { colorOverrides[key] }
    }

    func uiColorOverride(byString key: String) -> UIColor? {
        accessQueue.sync { uiColorOverrides[key] }
    }

    @objc private func handleUpdateNotification() {
        SVGCache.s.resetCache()
        NotificationCenter.default.post(name: updateSvgImagesNotification, object: nil)
    }
}
