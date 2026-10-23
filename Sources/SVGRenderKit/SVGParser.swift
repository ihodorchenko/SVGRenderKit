import UIKit

/// Parses an SVG document and produces renderable `CALayer` hierarchies.
public class SVGParser {

    fileprivate(set) var root: SVGRoot!

    private var xmlParser: XMLIndexer?
    
    private static func checkInputSize(_ bytes: Int) throws {
        guard bytes <= SVGInputLimits.maxInputBytes else {
            throw SVGError.content(text: "SVG source is \(bytes) bytes, over the \(SVGInputLimits.maxInputBytes)-byte limit")
        }
    }

    init(svgURL: URL, parsedRoot: SVGRoot?) throws {
        // A cache hit already holds the parsed tree: skip reading and XML-parsing the source.
        if let parsedRoot = parsedRoot {
            self.root = parsedRoot
        } else {
            let data = try Data(contentsOf: svgURL)
            try SVGParser.checkInputSize(data.count)
            xmlParser = SWXMLHash.parse(data)
            try parse()
        }
    }

    init(svgString: String, parsedRoot: SVGRoot?) throws {
        // A cache hit already holds the parsed tree: skip reading and XML-parsing the source.
        if let parsedRoot = parsedRoot {
            self.root = parsedRoot
        } else {
            try SVGParser.checkInputSize(svgString.utf8.count)
            xmlParser = SWXMLHash.parse(svgString)
            try parse()
        }
    }

    init(svgData: Data, name: String? = nil, parsedRoot: SVGRoot?) throws {
        // A cache hit already holds the parsed tree: skip reading and XML-parsing the source.
        if let parsedRoot = parsedRoot {
            self.root = parsedRoot
        } else {
            try SVGParser.checkInputSize(svgData.count)
            xmlParser = SWXMLHash.parse(svgData)
            try parse()
        }
    }

    /// Cache key for in-memory sources: the name *and* a digest of the full content, so reusing a
    /// name with different markup never returns a stale tree.
    ///
    /// A full MD5 of the content is used rather than `content.hashValue`: the latter is only a
    /// fixed-width hash, so a collision would return a foreign parsed tree (B113).
    private class func cacheKey(name: String, content: String) -> String {
        return SVGUtils.md5(name) + ":" + SVGUtils.md5(content)
    }

    private class func cacheKey(name: String, content: Data) -> String {
        return SVGUtils.md5(name) + ":" + SVGUtils.md5(content)
    }

    class func getParser(svgData: Data, name: String? = nil) throws -> SVGParser {
        let key = name.map { cacheKey(name: $0, content: svgData) }
        if SVGCache.s.isSVGParserUseCache == true, let key = key, let parsedRoot = SVGCache.s.get(md5: key) {
            let parser = try SVGParser(svgData: svgData, parsedRoot: parsedRoot)
            return parser
        }
        let generation = SVGCache.s.generation
        let parser = try SVGParser(svgData: svgData, parsedRoot: nil)
        if SVGCache.s.isSVGParserUseCache == true, let key = key {
            SVGCache.s.set(md5: key, object: parser.root, generation: generation)
        }
        return parser
    }

    class func getParser(svgString: String, name: String? = nil) throws -> SVGParser {
        let key = name.map { cacheKey(name: $0, content: svgString) }
        if SVGCache.s.isSVGParserUseCache == true, let key = key, let parsedRoot = SVGCache.s.get(md5: key) {
            let parser = try SVGParser(svgString: svgString, parsedRoot: parsedRoot)
            return parser
        }
        let generation = SVGCache.s.generation
        let parser = try SVGParser(svgString: svgString, parsedRoot: nil)
        if SVGCache.s.isSVGParserUseCache == true, let key = key {
            SVGCache.s.set(md5: key, object: parser.root, generation: generation)
        }
        return parser
    }

    /// Cache key for file sources: the URL (plus optional name) and the file's size and
    /// modification date, so a file rewritten at the same path is re-parsed.
    private class func cacheKey(url: URL, name: String?) -> String {
        var key = SVGUtils.md5(url.absoluteString)
        if let name = name { key = SVGUtils.md5(name) + ":" + key }
        // `URL.resourceValues` caches per instance and would return stale values; read attributes directly.
        if url.isFileURL, let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            key += ":\(size):\(mtime)"
        }
        return key
    }

    class func getParser(svgURL: URL, name: String? = nil) throws -> SVGParser {
        let key = cacheKey(url: svgURL, name: name)
        if SVGCache.s.isSVGParserUseCache == true, let parsedRoot = SVGCache.s.get(md5: key) {
            return try SVGParser(svgURL: svgURL, parsedRoot: parsedRoot)
        }
        let generation = SVGCache.s.generation
        let parser = try SVGParser(svgURL: svgURL, parsedRoot: nil)
        if SVGCache.s.isSVGParserUseCache == true {
            SVGCache.s.set(md5: key, object: parser.root, generation: generation)
        }
        return parser
    }

    internal func parse() throws {
        try SVGSignpost.interval("SVGParser.parse") {
            try parseDocument()
        }
    }

    private func parseDocument() throws {
        guard let xmlParser = xmlParser else {
            throw SVGError.parseError(text: "xmlParser == nil")
        }
        guard let svg = xmlParser["svg"][0].element else {
            makeParseError(error: SVGError.parseError(text: "no 'svg' tag"))
            throw SVGError.parseError(text: "no 'svg' tag")
        }

        // The object tree copies everything it needs out of the XML, so the DOM is released as
        // soon as the tree is built instead of living as long as the parser (and its cache entry).
        defer { self.xmlParser = nil }
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

    /// Builds and returns the root `CALayer` for the parsed SVG.
    /// - parameter overrideElements: Optional per-element style overrides applied while building the layer.
    /// - returns: The root layer, or throws an `SVGError` if the document cannot be rendered.
    public func getLayer(overrideElements: [String: SVGSourceStyleElement]?) throws -> CALayer {
        return try SVGSignpost.interval("SVGParser.getLayer") {
            try root.createLayer(overrideElements: overrideElements)
        }
    }
}
