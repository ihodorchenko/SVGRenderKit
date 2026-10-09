import UIKit

/// A `UIView` that renders an SVG document from a bundled asset, raw markup, or raw data.
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
    internal var svgData: Data?
    internal var svgDataName: String?

    /// The name of a bundled SVG resource to render. Setting this property triggers parsing.
    @IBInspectable open var SVGName: String? {
        get {
            return _SVGName
        }
        set {
            _SVGName = newValue
            if let SVGName = _SVGName {
                set(SVGName: SVGName, overrideElements: nil)
            }
        }
    }

    /// Renders the bundled SVG resource with the given name.
    open func set(SVGName: String) {
        self.set(SVGName: SVGName, overrideElements: nil)
    }

    /// Renders the bundled SVG resource with the given name, overriding fill colors by element name.
    /// - parameter fill_colors: A dictionary mapping SVG element names to fill colors.
    open func set(SVGName: String, fill_colors: [String: UIColor]?) {
        self.set(SVGName: SVGName, overrideElements: overrideElements(from: fill_colors))
    }

    /// Renders the bundled SVG resource with the given name, overriding the style of specific elements.
    /// - parameter overrideElements: A dictionary mapping element names to their override styles.
    open func set(SVGName: String, overrideElements: [String: SVGSourceStyleElement]?) {
        _SVGName = SVGName
        self.overrideElements = overrideElements
        #if !TARGET_INTERFACE_BUILDER
            let bundle = Bundle.main
        #else
            let bundle = NSBundle(forClass: type(of: self))
        #endif

        let url = bundle.bundleURL.appendingPathComponent(SVGName, isDirectory: false)
        load(.url(url), overrideElements: overrideElements)
    }

    var _svgString: String?

    /// The raw SVG markup to render. Setting this property triggers parsing.
    open var svgString: String? {
        get {
            return _svgString
        }
        set {
            _svgString = newValue
            if let svgString = _svgString {
                set(svgString: svgString, name: nil, overrideElements: nil)
            }
        }
    }

    /// Renders the given SVG markup, overriding fill colors by element name.
    /// - parameter name: An optional identifier used for caching.
    /// - parameter fill_colors: A dictionary mapping element names to fill colors.
    open func set(svgString: String, name: String? = nil, fill_colors: [String: UIColor]? = nil) {
        self.set(svgString: svgString, name: name, overrideElements: overrideElements(from: fill_colors))
    }

    /// Renders the given SVG markup, overriding the style of specific elements.
    /// - parameter name: An optional identifier used for caching.
    /// - parameter overrideElements: A dictionary mapping element names to their override styles.
    open func set(svgString: String, name: String?, overrideElements: [String: SVGSourceStyleElement]?) {
        self.overrideElements = overrideElements
        load(.string(svgString, name: name), overrideElements: overrideElements)
    }

    /// Renders the given SVG data, overriding fill colors by element name.
    /// - parameter name: An optional identifier used for caching.
    /// - parameter fill_colors: A dictionary mapping element names to fill colors.
    open func set(svgData: Data, name: String? = nil, fill_colors: [String: UIColor]? = nil) {
        self.set(svgData: svgData, name: name, overrideElements: overrideElements(from: fill_colors))
    }

    /// Renders the given SVG data, overriding the style of specific elements.
    /// - parameter name: An optional identifier used for caching.
    /// - parameter overrideElements: A dictionary mapping element names to their override styles.
    open func set(svgData: Data, name: String? = nil, overrideElements: [String: SVGSourceStyleElement]? = nil) {
        self.svgData = svgData
        self.svgDataName = name
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

    /// Parses and renders the given source asynchronously, discarding stale results.
    private func load(_ source: LoadSource, overrideElements: [String: SVGSourceStyleElement]?) {
        loadGeneration += 1
        let generation = loadGeneration

        DispatchQueue.global().async {
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

                let layer = try parser.getLayer(overrideElements: overrideElements)

                DispatchQueue.main.async {
                    guard generation == self.loadGeneration else { return }
                    self.parser = parser
                    self.shapeLayer = layer
                    self.set(layer: layer)
                }
            } catch {
                SVGLog.addSLog(errorStr: "SVG load error: \(error.localizedDescription)")
            }
        }
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

    /// Unsupported initializer; the view cannot be decoded from a nib or storyboard.
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        if let _SVGName = _SVGName {
            set(SVGName: _SVGName, overrideElements: self.overrideElements)
        } else if let svgData = svgData {
            set(svgData: svgData, name: svgDataName, overrideElements: self.overrideElements)
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

        var transform = CATransform3DIdentity
        transform = CATransform3DTranslate(transform, -viewBox.origin.x, -viewBox.origin.y, 0)
        transform = CATransform3DScale(transform, resolved.scaleX, resolved.scaleY, 1)
        transform = CATransform3DTranslate(transform, resolved.translateX, resolved.translateY, 0)
        shapeLayer.transform = transform

        contentView.frame = self.bounds
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
