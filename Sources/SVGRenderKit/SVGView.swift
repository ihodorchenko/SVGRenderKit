import UIKit

/// A `UIView` that renders an SVG document from a bundled asset, raw markup, or raw data.
///
/// Like any `UIView` it should be used from the main thread; loads requested from other threads
/// are marshalled onto the main queue.
open class SVGView: UIView {

    private enum LoadSource {
        case url(URL)
        case string(String, name: String?)
        case data(Data, name: String?)
    }

    var shapeLayer: CALayer?
    var parser: SVGParser?
    var contentView: UIView = UIView()

    internal static var updateNotificationName: NSNotification.Name?

    /// Parsing and layer building share per-document state (`SVGOptions.renderScale` on cached roots),
    /// so loads run one at a time on a single background queue: this also bounds the thread count
    /// when many views are created at once.
    private static let loadQueue = DispatchQueue(label: "SVGRenderKit.SVGView.load", qos: .userInitiated)

    /// The `renderScale` the current layer was rasterized with; `nil` if the view had no size yet.
    internal private(set) var renderedScale: CGFloat?
    /// Whether the current document contains patterns (whose tiles depend on `renderScale`).
    internal private(set) var rendersPatterns = false

    /// Tracks the latest requested load so stale async results are discarded.
    private var loadGeneration: Int = 0

    /// Whether the shared parser cache is enabled, applied across all `SVGView` instances.
    public static var isSVGParserUseCache: Bool {
        get {
            return SVGCache.s.isSVGParserUseCache
        }
        set {
            SVGCache.s.isSVGParserUseCache = newValue
        }
    }

    private(set) var overrideElements: [String: SVGSourceStyleElement]?

    internal var _SVGName: String?
    /// The last requested source, replayed when the update notification fires.
    private var currentSource: LoadSource?

    /// The name of a bundled SVG resource to render. Setting this property triggers parsing.
    @IBInspectable open var SVGName: String? {
        get {
            return _SVGName
        }
        set {
            if let SVGName = newValue {
                set(SVGName: SVGName, overrideElements: nil)
            } else if _SVGName != nil {
                resetContent()
            }
        }
    }

    /// Renders the bundled SVG resource with the given name.
    open func set(SVGName: String) {
        self.set(SVGName: SVGName, overrideElements: nil)
    }

    /// Renders the bundled SVG resource with the given name, overriding fill colors by element name.
    /// - parameter SVGName: The name of the bundled SVG resource to render.
    /// - parameter fill_colors: A dictionary mapping SVG element names to fill colors.
    open func set(SVGName: String, fill_colors: [String: UIColor]?) {
        self.set(SVGName: SVGName, overrideElements: overrideElements(from: fill_colors))
    }

    /// Renders the bundled SVG resource with the given name, overriding the style of specific elements.
    /// - parameter SVGName: The name of the bundled SVG resource to render.
    /// - parameter overrideElements: A dictionary mapping element names to their override styles.
    open func set(SVGName: String, overrideElements: [String: SVGSourceStyleElement]?) {
        set(SVGName: SVGName, bundle: nil, overrideElements: overrideElements)
    }

    /// Renders the SVG resource with the given name from the given bundle (e.g. a framework or Swift Package resource bundle).
    /// - parameter SVGName: The name of the SVG resource to render.
    /// - parameter bundle: The bundle containing the resource; `nil` means `Bundle.main`.
    /// - parameter overrideElements: A dictionary mapping element names to their override styles.
    open func set(SVGName: String, bundle: Bundle?, overrideElements: [String: SVGSourceStyleElement]? = nil) {
        _SVGName = SVGName
        _svgString = nil
        self.overrideElements = overrideElements
        #if !TARGET_INTERFACE_BUILDER
            let bundle = bundle ?? Bundle.main
        #else
            let bundle = bundle ?? Bundle(for: type(of: self))
        #endif

        let url = bundle.bundleURL.appendingPathComponent(SVGName, isDirectory: false)
        load(.url(url), overrideElements: overrideElements)
    }

    /// Renders the SVG file at the given URL, overriding the style of specific elements.
    /// Changes to the file are picked up on the next call (the parser cache is keyed by file size and modification date).
    /// - parameter svgURL: The file URL of the SVG to render.
    /// - parameter overrideElements: A dictionary mapping element names to their override styles.
    open func set(svgURL: URL, overrideElements: [String: SVGSourceStyleElement]? = nil) {
        _SVGName = nil
        _svgString = nil
        self.overrideElements = overrideElements
        load(.url(svgURL), overrideElements: overrideElements)
    }

    var _svgString: String?

    /// The raw SVG markup to render. Setting this property triggers parsing.
    open var svgString: String? {
        get {
            return _svgString
        }
        set {
            if let svgString = newValue {
                set(svgString: svgString, name: nil, overrideElements: nil)
            } else if _svgString != nil {
                resetContent()
            }
        }
    }

    /// Renders the given SVG markup, overriding fill colors by element name.
    /// - parameter svgString: The raw SVG markup to render.
    /// - parameter name: An optional identifier used for caching.
    /// - parameter fill_colors: A dictionary mapping element names to fill colors.
    open func set(svgString: String, name: String? = nil, fill_colors: [String: UIColor]? = nil) {
        self.set(svgString: svgString, name: name, overrideElements: overrideElements(from: fill_colors))
    }

    /// Renders the given SVG markup, overriding the style of specific elements.
    /// - parameter svgString: The raw SVG markup to render.
    /// - parameter name: An optional identifier used for caching.
    /// - parameter overrideElements: A dictionary mapping element names to their override styles.
    open func set(svgString: String, name: String?, overrideElements: [String: SVGSourceStyleElement]?) {
        _SVGName = nil
        _svgString = svgString
        self.overrideElements = overrideElements
        load(.string(svgString, name: name), overrideElements: overrideElements)
    }

    /// Renders the given SVG data, overriding fill colors by element name.
    /// - parameter svgData: The raw SVG data to render.
    /// - parameter name: An optional identifier used for caching.
    /// - parameter fill_colors: A dictionary mapping element names to fill colors.
    open func set(svgData: Data, name: String? = nil, fill_colors: [String: UIColor]? = nil) {
        self.set(svgData: svgData, name: name, overrideElements: overrideElements(from: fill_colors))
    }

    /// Renders the given SVG data, overriding the style of specific elements.
    /// - parameter svgData: The raw SVG data to render.
    /// - parameter name: An optional identifier used for caching.
    /// - parameter overrideElements: A dictionary mapping element names to their override styles.
    open func set(svgData: Data, name: String? = nil, overrideElements: [String: SVGSourceStyleElement]? = nil) {
        _SVGName = nil
        _svgString = nil
        self.overrideElements = overrideElements
        load(.data(svgData, name: name), overrideElements: overrideElements)
    }

    /// Converts a fill-color dictionary into the style-override representation.
    private func overrideElements(from fillColors: [String: UIColor]?) -> [String: SVGSourceStyleElement]? {
        guard let fillColors = fillColors else { return nil }
        var result: [String: SVGSourceStyleElement] = [:]
        for (key, color) in fillColors {
            result[key] = SVGSourceStyleElement(fill: color, stroke: nil, strokeWidth: nil)
        }
        return result
    }

    /// Hands the parser and layer built off-main over to the main thread, which owns them from then on.
    private struct LoadResult: @unchecked Sendable {
        let parser: SVGParser
        let layer: CALayer
    }

    /// Parses and renders the given source asynchronously, discarding stale results.
    private func load(_ source: LoadSource, overrideElements: [String: SVGSourceStyleElement]?) {
        // Reads `bounds`/`window` and owns `loadGeneration`: UIKit state is main-thread only,
        // so calls from other threads are marshalled onto the main queue.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.load(source, overrideElements: overrideElements) }
            return
        }
        currentSource = source
        loadGeneration += 1
        let generation = loadGeneration
        let containerSize = bounds.size
        // `UIScreen` is main-thread API; capture the scale here for the background render.
        SVGTextTag.screenScale = window?.screen.scale ?? UIScreen.main.scale

        SVGView.loadQueue.async {
            do {
                let parser: SVGParser
                switch source {
                case .url(let url):
                    parser = try SVGParser.getParser(svgURL: url)
                case .string(let string, let name):
                    parser = try SVGParser.getParser(svgString: string, name: name)
                case .data(let data, let name):
                    parser = try SVGParser.getParser(svgData: data, name: name)
                }

                // Rasterize paint servers (patterns) at the final output resolution
                // rather than the device screen scale, so their anti-aliasing matches
                // the on-screen result independently of the render destination.
                let options = parser.root.getSvgOptions()
                let viewBox = options.viewBox
                var scale: CGFloat?
                if containerSize.width > 0, containerSize.height > 0,
                   viewBox.width > 0, viewBox.height > 0 {
                    let resolved = options.preserveAspectRatio.resolve(viewBox: viewBox, containerSize: containerSize)
                    scale = max(resolved.scaleX, resolved.scaleY)
                    options.renderScale = scale!
                }

                let layer = try parser.getLayer(overrideElements: overrideElements)
                let usesPatterns = options.usesPatterns

                // The layer tree is built on the load queue and only touched on main afterwards.
                let result = LoadResult(parser: parser, layer: layer)
                DispatchQueue.main.async {
                    guard generation == self.loadGeneration else { return }
                    self.renderedScale = scale
                    self.rendersPatterns = usesPatterns
                    self.parser = result.parser
                    self.shapeLayer = result.layer
                    self.set(layer: result.layer)
                }
            } catch {
                SVGLog.addSLog(errorStr: "SVG load error: \(error.localizedDescription)")
            }
        }
    }

    /// Drops the current source and rendered content, and invalidates any in-flight load.
    private func resetContent() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.resetContent() }
            return
        }
        loadGeneration += 1
        currentSource = nil
        _SVGName = nil
        _svgString = nil
        overrideElements = nil
        clear()
        shapeLayer = nil
        parser = nil
        renderedScale = nil
        rendersPatterns = false
    }

    private func set(layer: CALayer) {
        clear()
        self.contentView.layer.addSublayer(layer)
        update()
    }

    /// Marks the view as needing layout so the rendered SVG is re-fitted.
    open func update() {
        self.setNeedsLayout()
    }

    /// Removes the currently rendered SVG layers from the view.
    open func clear() {
        if let sublayers = self.contentView.nonOptionalLayer.sublayers {
            for sublayer in sublayers {
                sublayer.removeFromSuperlayer()
            }
        }
        self.shapeLayer?.removeFromSuperlayer()
    }

    /// Creates an empty `SVGView`.
    public init() {
        super.init(frame: CGRect.zero)
        initView()
    }

    /// Creates an `SVGView` with the given frame.
    override public init(frame: CGRect) {
        super.init(frame: frame)
        initView()
    }

    /// Creates an `SVGView` from a nib or storyboard; `SVGName` can be set in Interface Builder.
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        initView()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func initView() {
        if let name = SVGView.updateNotificationName {
            NotificationCenter.default.addObserver(self, selector: #selector(updateSvg), name: name, object: nil)
        }
        contentView.clipsToBounds = true
        self.addSubview(contentView)
    }

    @objc internal func updateSvg() {
        if let source = currentSource {
            load(source, overrideElements: overrideElements)
        }
    }

    /// Lays out the rendered SVG, scaling and translating it to fit the view's bounds.
    open override func layoutSubviews() {
        super.layoutSubviews()
        guard let parser = parser, let shapeLayer = shapeLayer else { return }

        let options = parser.root.svgElement.options
        let viewBox = options.viewBox
        let containingSize = self.bounds.size
        let resolved = options.preserveAspectRatio.resolve(viewBox: viewBox, containerSize: containingSize)

        // Build Translate(center) · Scale(scale) · Translate(-origin) so the
        // centering is applied in container space (not multiplied by scale),
        // and the viewBox origin offset is applied in viewBox space (scaled).
        var transform = CATransform3DIdentity
        transform = CATransform3DTranslate(transform, resolved.translateX, resolved.translateY, 0)
        transform = CATransform3DScale(transform, resolved.scaleX, resolved.scaleY, 1)
        transform = CATransform3DTranslate(transform, -viewBox.origin.x, -viewBox.origin.y, 0)
        shapeLayer.transform = transform

        contentView.frame = self.bounds

        // Pattern tiles are rasterized at the scale known at load time. If the view had no size
        // then (or has grown noticeably since), re-render so tiles are not blurry.
        if rendersPatterns, let source = currentSource, containingSize.width > 0, containingSize.height > 0,
           viewBox.width > 0, viewBox.height > 0 {
            let needed = max(resolved.scaleX, resolved.scaleY)
            if renderedScale == nil || needed > (renderedScale ?? 0) * 1.5 {
                load(source, overrideElements: overrideElements)
            }
        }
    }
}

extension SVGView {
    /// Creates an `SVGView` that renders the bundled SVG resource with the given name.
    public convenience init(SVGName: String) {
        self.init()
        self.SVGName = SVGName
    }

    /// Creates an `SVGView` that renders the given SVG markup.
    public convenience init(svgString: String) {
        self.init()
        self.svgString = svgString
    }
}
