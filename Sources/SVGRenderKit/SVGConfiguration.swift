import UIKit

/// Central, shared configuration for the renderer: parser caching, reload
/// notifications, and global color overrides.
public final class SVGConfiguration: @unchecked Sendable {
    /// The shared configuration instance.
    public static let shared = SVGConfiguration()

    /// Whether parsed SVG roots are cached. Defaults to `true`.
    public var isParserCacheEnabled: Bool {
        get { cacheEnabledLock.lock(); defer { cacheEnabledLock.unlock() }; return _isParserCacheEnabled }
        set { cacheEnabledLock.lock(); defer { cacheEnabledLock.unlock() }; _isParserCacheEnabled = newValue }
    }

    private let cacheEnabledLock = NSLock()
    private var _isParserCacheEnabled: Bool = true

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
            }
        }
    }

    let updateSvgImagesNotification = NSNotification.Name("SVGView_updateSvgImagesNSNotification")

    private let accessQueue = DispatchQueue(label: "SVG.Configuration", attributes: .concurrent)
    private var colorOverrides: [String: String] = [:]
    private var uiColorOverrides: [String: UIColor] = [:]

    private init() {}

    /// Adds name-to-color-string overrides that take precedence when resolving colors.
    func addColorOverrides(_ colors: [String: String]) {
        accessQueue.sync(flags: .barrier) {
            for (key, value) in colors { self.colorOverrides[SVGConfiguration.normalized(key)] = value }
        }
        // Colors are resolved while parsing, so cached trees must be dropped (B114).
        SVGCache.s.resetCache()
    }

    /// Replaces all name-to-color-string overrides.
    func setColorOverrides(_ colors: [String: String]) {
        accessQueue.sync(flags: .barrier) {
            self.colorOverrides = colors.reduce(into: [:]) { $0[SVGConfiguration.normalized($1.key)] = $1.value }
        }
        SVGCache.s.resetCache()
    }

    /// Adds name-to-`UIColor` overrides that take precedence when resolving colors.
    func addUIColorOverrides(_ colors: [String: UIColor]) {
        accessQueue.sync(flags: .barrier) {
            for (key, value) in colors { self.uiColorOverrides[SVGConfiguration.normalized(key)] = value }
        }
        SVGCache.s.resetCache()
    }

    /// Replaces all name-to-`UIColor` overrides.
    func setUIColorOverrides(_ colors: [String: UIColor]) {
        accessQueue.sync(flags: .barrier) {
            self.uiColorOverrides = colors.reduce(into: [:]) { $0[SVGConfiguration.normalized($1.key)] = $1.value }
        }
        SVGCache.s.resetCache()
    }

    /// Color keywords are case-insensitive, so an override key is matched the same way
    /// the color string is (B109).
    private static func normalized(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func colorOverride(byString key: String) -> String? {
        accessQueue.sync { colorOverrides[SVGConfiguration.normalized(key)] }
    }

    func uiColorOverride(byString key: String) -> UIColor? {
        accessQueue.sync { uiColorOverrides[SVGConfiguration.normalized(key)] }
    }

    @objc private func handleUpdateNotification() {
        SVGCache.s.resetCache()
        NotificationCenter.default.post(name: updateSvgImagesNotification, object: nil)
    }
}
