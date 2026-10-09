import UIKit

/// Parses an SVG document and produces renderable `CALayer` hierarchies.
open class SVGParser {

    fileprivate(set) var root: SVGRoot!
    /// When `true`, parsing is limited to a single path rather than a full document.
    open var shouldParseSinglePathOnly = false

    fileprivate var xmlParser: XMLIndexer?
    
    init(svgURL: URL, containerLayer: CALayer? = nil, parsedRoot: SVGRoot?) throws {
        let data = try Data(contentsOf: svgURL)
        xmlParser = SWXMLHash.parse(data)
        _init()
        if let parsedRoot = parsedRoot {
            self.root = parsedRoot
        } else {
            try parse()
        }
    }

    init(svgString: String, containerLayer: CALayer? = nil, parsedRoot: SVGRoot?) throws {
        xmlParser = SWXMLHash.parse(svgString)
        _init()
        if let parsedRoot = parsedRoot {
            self.root = parsedRoot
        } else {
            try parse()
        }
    }

    init(svgData: Data, name: String? = nil, containerLayer: CALayer? = nil, parsedRoot: SVGRoot?) throws {
        xmlParser = SWXMLHash.parse(svgData)
        _init()
        if let parsedRoot = parsedRoot {
            self.root = parsedRoot
        } else {
            try parse()
        }
    }

    class func getParser(svgData: Data, name: String? = nil) throws -> SVGParser {
        if SVGCache.s.isSVGParserUseCache == true, let name = name, let parsedRoot = SVGCache.s.get(md5: SVGUtils.md5(name)) {
            let parser = try SVGParser(svgData: svgData, parsedRoot: parsedRoot)
            return parser
        }
        let parser = try SVGParser(svgData: svgData, parsedRoot: nil)
        if SVGCache.s.isSVGParserUseCache == true, let name = name {
            SVGCache.s.set(md5: SVGUtils.md5(name), object: parser.root)
        }
        return parser
    }

    class func getParser(svgString: String, name: String? = nil) throws -> SVGParser {
        if SVGCache.s.isSVGParserUseCache == true, let name = name, let parsedRoot = SVGCache.s.get(md5: SVGUtils.md5(name)) {
            let parser = try SVGParser(svgString: svgString, parsedRoot: parsedRoot)
            return parser
        }
        let parser = try SVGParser(svgString: svgString, parsedRoot: nil)
        if SVGCache.s.isSVGParserUseCache == true, let name = name {
            SVGCache.s.set(md5: SVGUtils.md5(name), object: parser.root)
        }
        return parser
    }

    class func getParser(svgURL: URL, name: String? = nil) throws -> SVGParser {
        if SVGCache.s.isSVGParserUseCache == true, let name = name, let parsedRoot = SVGCache.s.get(md5: SVGUtils.md5(name)) {
            let parser = try SVGParser(svgURL: svgURL, parsedRoot: parsedRoot)
            return parser
        }
        if SVGCache.s.isSVGParserUseCache == true, let parsedRoot = SVGCache.s.get(md5: SVGUtils.md5(svgURL.absoluteString)) {
            let parser = try SVGParser(svgURL: svgURL, parsedRoot: parsedRoot)
            return parser
        }
        let parser = try SVGParser(svgURL: svgURL, parsedRoot: nil)
        if SVGCache.s.isSVGParserUseCache == true {
            if let name = name {
                SVGCache.s.set(md5: SVGUtils.md5(name), object: parser.root)
            } else {
                SVGCache.s.set(md5: SVGUtils.md5(svgURL.absoluteString), object: parser.root)
            }
        }
        return parser
    }

    private func _init() {
    }

    internal func parse() throws {
        guard let xmlParser = xmlParser else {
            throw SVGError.parseError(text: "xmlParser == nil")
        }
        guard let svg = xmlParser["svg"][0].element else {
            makeParseError(error: SVGError.parseError(text: "no 'svg' tag"))
            throw SVGError.parseError(text: "no 'svg' tag")
        }

        do {
            root = try SVGRoot(xmlSvgElement: svg)
        } catch let error as SVGError {
            throw error
        } catch {
            throw SVGError.unexpectedError(text: "when parse SVGSVGTag")
        }


    }

    func makeParseError(error: SVGError) {
        SVGLog.addLog(svgError: error)
    }
    func makeError(error: Error) {
        SVGLog.addSLog(errorStr: error.localizedDescription)
    }

    /// Builds and returns the root `CALayer` for the parsed SVG.
    /// - parameter overrideElements: Optional per-element style overrides applied while building the layer.
    /// - returns: The root layer, or throws an `SVGError` if the document cannot be rendered.
    open func getLayer(overrideElements: [String: SVGSourceStyleElement]?) throws -> CALayer {
        return try root.createLayer(overrideElements: overrideElements)
    }
}
