import UIKit

/// Parses an SVG `<style>` block into ordered rules, resolved against an element's tag,
/// classes and id.
open class SVGStyleTag: SVGChildObject {
    class override var key: String { get { return "style" }}

    /// One parsed rule: the simple selector it matches (`.a`, `#u`, `rect` — the same form
    /// `SVGObject.classNames` and `SVGObject.id` use) and the declarations it sets.
    struct Rule {
        let key: String
        let declarations: SVGSourceStyleElement
    }

    /// The rules in document order, one list per selector kind: within a kind a later rule
    /// wins, and the kinds keep their coarse specificity order — tag, then class, then id
    /// (full CSS specificity is out of scope). Three dictionaries lost the order (B90); a
    /// flat list lost the specificity buckets, so it is both (B119-7).
    private(set) var tagRules: [Rule] = []
    private(set) var classRules: [Rule] = []
    private(set) var idRules: [Rule] = []

    /// The declarations of every rule that matches `object`, in cascade order: a later rule
    /// wins whatever order the element lists its classes in (B119-7).
    func style(for object: SVGObject) -> SVGSourceStyleElement {
        var style = SVGSourceStyleElement()
        for rule in tagRules where rule.key == object.key {
            style = style.combine(child: rule.declarations)
        }
        for rule in classRules where object.classNames.contains(rule.key) {
            style = style.combine(child: rule.declarations)
        }
        if let id = object.id {
            for rule in idRules where rule.key == id {
                style = style.combine(child: rule.declarations)
            }
        }
        return style
    }

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

    /// Applies one rule to every simple selector it lists, keeping the rules in document
    /// order: a later rule wins, whether a repeated selector only adds properties or the
    /// element lists several classes (B90, B119-7).
    private func applyRule(selectors: String, declarations: String) throws {
        guard !declarations.isEmpty else { return }
        for raw in selectors.split(separator: ",") {
            let selector = SVGUtils.trimmed(string: String(raw))
            guard let target = SVGStyleTag.selectorTarget(selector) else {
                // Combinators, compound selectors, `*` and at-rules are out of scope.
                continue
            }
            let element = SVGSourceStyleElement()
            try element.set(styleStr: declarations, force: true)
            let rule = Rule(key: target.key, declarations: element)
            switch target.kind {
            case .tagSelector: tagRules.append(rule)
            case .classSelector: classRules.append(rule)
            case .idSelector: idRules.append(rule)
            }
        }
    }

    /// Maps a selector to its kind and key — the selector itself, so it can be matched
    /// against the dotted class names and prefixed ids of `SVGObject` — or `nil` when it is
    /// not a simple class / id / tag selector.
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

    /// Splits a stylesheet into `(selectors, declarations)` rules in document order.
    /// At-rules are skipped: a block at-rule (`@media`) with its whole body, and a statement
    /// at-rule (`@import …;`, `@charset …;`) without eating the rule that follows it — its
    /// prelude shares the upcoming `{` with the next selector (B119-7).
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
            var prelude = SVGUtils.trimmed(string: selector)
            // A statement at-rule ends at its last ';': the rest of the prelude is this
            // block's selector, not part of the at-rule.
            if prelude.hasPrefix("@"), let semicolon = prelude.lastIndex(of: ";") {
                prelude = SVGUtils.trimmed(string: String(prelude[prelude.index(after: semicolon)...]))
            }
            if prelude.isEmpty || prelude.hasPrefix("@") {
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
            rules.append((prelude, body))
        }
        return rules
    }
}
