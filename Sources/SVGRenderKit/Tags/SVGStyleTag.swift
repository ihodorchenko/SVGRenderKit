import UIKit

/// Parses an SVG `<style>` block into selectors grouped by id, class, and tag name.
open class SVGStyleTag: SVGChildObject {
    class override var key: String { get { return "style" }}

    private(set) var byIdDict: [String: SVGSourceStyleElement] = [:]
    private(set) var byClassDict: [String: SVGSourceStyleElement] = [:]
    private(set) var byTagDict: [String: SVGSourceStyleElement] = [:]

    /// Initializes a style tag by parsing the text content of the `<style>` element.
    public required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGGroupProtocol) throws {
        try super.init(xmlElement: xmlElement, addDict: addDict, parent: parent)

        try parseStyle(styleStr: xmlElement.text)
    }

    func parseStyle(styleStr: String) throws {
        for rule in SVGStyleTag.cssRules(in: SVGStyleTag.removingComments(styleStr)) {
            try applyRule(selectors: rule.selectors, declarations: rule.declarations)
        }
    }

    private enum SelectorKind { case classSelector, idSelector, tagSelector }
    private struct SelectorTarget { let kind: SelectorKind; let key: String }

    /// Applies one rule to every simple selector it lists. Declarations for a repeated
    /// selector accumulate (later properties win) and rules are processed in document
    /// order; a `[String: String]` used before lost both (B90).
    private func applyRule(selectors: String, declarations: String) throws {
        guard !declarations.isEmpty else { return }
        for raw in selectors.split(separator: ",") {
            let selector = SVGUtils.trimmed(string: String(raw))
            guard let target = SVGStyleTag.selectorTarget(selector) else {
                // Combinators, compound selectors, `*` and at-rules are out of scope.
                continue
            }
            let element = existingElement(for: target) ?? SVGSourceStyleElement()
            try element.set(styleStr: declarations, force: true)
            store(element, for: target)
        }
    }

    private func existingElement(for target: SelectorTarget) -> SVGSourceStyleElement? {
        switch target.kind {
        case .classSelector: return byClassDict[target.key]
        case .idSelector: return byIdDict[target.key]
        case .tagSelector: return byTagDict[target.key]
        }
    }

    private func store(_ element: SVGSourceStyleElement, for target: SelectorTarget) {
        switch target.kind {
        case .classSelector: byClassDict[target.key] = element
        case .idSelector: byIdDict[target.key] = element
        case .tagSelector: byTagDict[target.key] = element
        }
    }

    /// Maps a selector to a dictionary key, or `nil` when it is not a simple
    /// class / id / tag selector.
    private static func selectorTarget(_ selector: String) -> SelectorTarget? {
        if selector.hasPrefix(".") {
            let name = String(selector.dropFirst())
            return isSimpleName(name) ? SelectorTarget(kind: .classSelector, key: selector) : nil
        }
        if selector.hasPrefix("#") {
            let name = String(selector.dropFirst())
            return isSimpleName(name) ? SelectorTarget(kind: .idSelector, key: selector) : nil
        }
        if let first = selector.first, first.isLetter, isSimpleName(selector) {
            return SelectorTarget(kind: .tagSelector, key: selector)
        }
        return nil
    }

    private static func isSimpleName(_ name: String) -> Bool {
        return !name.isEmpty && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    /// Removes `/* … */` comments, including across lines.
    private static func removingComments(_ text: String) -> String {
        var result = ""
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            if chars[i] == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                i += 2
                while i + 1 < chars.count, !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                i = min(i + 2, chars.count)
            } else {
                result.append(chars[i])
                i += 1
            }
        }
        return result
    }

    /// Splits a stylesheet into `(selectors, declarations)` rules in document order,
    /// skipping at-rules such as `@media` together with their nested blocks.
    private static func cssRules(in text: String) -> [(selectors: String, declarations: String)] {
        var rules: [(selectors: String, declarations: String)] = []
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            var selector = ""
            while i < chars.count, chars[i] != "{" {
                selector.append(chars[i])
                i += 1
            }
            guard i < chars.count else { break }
            i += 1 // consume '{'
            if SVGUtils.trimmed(string: selector).hasPrefix("@") {
                var depth = 1
                while i < chars.count, depth > 0 {
                    if chars[i] == "{" { depth += 1 }
                    else if chars[i] == "}" { depth -= 1 }
                    i += 1
                }
                continue
            }
            var body = ""
            while i < chars.count, chars[i] != "}" {
                body.append(chars[i])
                i += 1
            }
            if i < chars.count { i += 1 } // consume '}'
            rules.append((SVGUtils.trimmed(string: selector), body))
        }
        return rules
    }
}
