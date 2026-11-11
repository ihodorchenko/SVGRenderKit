import UIKit

/// A document-wide CSS stylesheet: every `<style>` block of the document, in document order.
///
/// The profile matches simple selectors (tag / `.class` / `#id`), compound selectors
/// (`path.a#b`, `*`) and descendant lists (`.wA path`). Combinators (`>`, `+`, `~`),
/// pseudo-classes, attribute selectors and at-rules other than `@keyframes` are out of scope and
/// dropped (see CONFORMANCE.md). The cascade honours specificity and source order, and
/// `!important` declarations are applied after every normal declaration.
final class SVGStyleSheet {

    // MARK: - Selector model

    /// One compound selector: a tag, classes and an id. `tag == nil` means the universal selector.
    struct Compound {
        let tag: String?
        /// Classes with the `.` prefix, the form `SVGObject.classNames` keeps.
        let classes: [String]
        /// The id with the `#` prefix, the form `SVGObject.id` keeps.
        let id: String?

        func matches(_ object: SVGObject) -> Bool {
            if let tag = tag, tag != object.key { return false }
            if let id = id, id != object.id { return false }
            if !classes.isEmpty, !Set(classes).isSubset(of: Set(object.classNames)) { return false }
            return true
        }

        var specificity: (Int, Int, Int) {
            return (id == nil ? 0 : 1, classes.count, tag == nil ? 0 : 1)
        }
    }

    /// A selector chain of descendant compounds, ancestor first and subject last.
    struct Selector {
        let compounds: [Compound]

        var specificity: (Int, Int, Int) {
            return compounds.reduce((0, 0, 0)) { total, compound in
                let value = compound.specificity
                return (total.0 + value.0, total.1 + value.1, total.2 + value.2)
            }
        }
    }

    /// The declarations of one rule, split by priority.
    struct Declarations {
        let normal: SVGSourceStyleElement
        let important: SVGSourceStyleElement
        let rawNormal: [(property: String, value: String)]
        let rawImportant: [(property: String, value: String)]
    }

    /// One style rule with its place in the cascade.
    struct Rule {
        let selector: Selector
        let declarations: Declarations
        let order: Int
    }

    /// One keyframe of a `@keyframes` block.
    struct Keyframe {
        let offset: Double
        let declarations: [String: String]
    }

    /// A parsed `@keyframes` block, sorted by offset.
    struct Keyframes {
        let frames: [Keyframe]
    }

    private(set) var rules: [Rule] = []
    private(set) var keyframes: [String: Keyframes] = [:]

    // MARK: - Parsing

    /// Parses every `<style>` block under the document's root `<svg>` element, in document order.
    init(root xmlElement: XMLElement) {
        var styleTexts: [String] = []
        SVGStyleSheet.collectStyleTexts(xmlElement, into: &styleTexts)
        var order = 0
        for text in styleTexts {
            parse(styleText: text, order: &order)
        }
    }

    private static func collectStyleTexts(_ element: XMLElement, into texts: inout [String]) {
        if element.name == "style" {
            texts.append(element.text)
            return
        }
        for child in element.xmlChildren {
            collectStyleTexts(child, into: &texts)
        }
    }

    private func parse(styleText: String, order: inout Int) {
        for block in SVGStyleSheet.blocks(in: SVGStyleSheet.removingComments(styleText)) {
            if block.prelude.hasPrefix("@") {
                parseAtRule(prelude: block.prelude, body: block.body)
                continue
            }
            let declarations = SVGStyleSheet.parseDeclarations(block.body)
            for selectorText in SVGStyleSheet.splitSelectors(block.prelude) {
                guard let selector = SVGStyleSheet.parseSelector(selectorText) else { continue }
                rules.append(Rule(selector: selector, declarations: declarations, order: order))
                order += 1
            }
        }
    }

    /// `@keyframes` become a registry; every other at-rule (`@media`, `@font-face`, `@supports`,
    /// …) stays out of scope and is skipped with its body.
    private func parseAtRule(prelude: String, body: String) {
        let withoutAt = prelude.dropFirst() // the leading '@'
        guard let separator = withoutAt.firstIndex(where: { $0.isWhitespace }) else { return }
        let name = String(withoutAt[..<separator]).lowercased()
        guard name == "keyframes" || name.hasSuffix("-keyframes") else { return }
        let animationName = SVGUtils.trimmed(string: String(withoutAt[separator...]))
        guard !animationName.isEmpty else { return }

        var frames: [Keyframe] = []
        for block in SVGStyleSheet.blocks(in: body) {
            let offsets = SVGStyleSheet.keyframeOffsets(block.prelude)
            guard !offsets.isEmpty else { continue }
            var declarations: [String: String] = [:]
            for declaration in SVGSourceStyleElement.orderedDeclarations(from: block.body) {
                declarations[declaration.property] = declaration.value
            }
            for offset in offsets {
                frames.append(Keyframe(offset: offset, declarations: declarations))
            }
        }
        frames.sort { $0.offset < $1.offset }
        keyframes[animationName] = Keyframes(frames: frames)
    }

    private static func parseDeclarations(_ body: String) -> Declarations {
        var normal: [String: String] = [:]
        var important: [String: String] = [:]
        var rawNormal: [(property: String, value: String)] = []
        var rawImportant: [(property: String, value: String)] = []
        for declaration in SVGSourceStyleElement.declarationsWithImportance(from: body) {
            if declaration.important {
                important[declaration.property] = declaration.value
                rawImportant.append((declaration.property, declaration.value))
            } else {
                normal[declaration.property] = declaration.value
                rawNormal.append((declaration.property, declaration.value))
            }
        }
        let normalStyle = SVGSourceStyleElement()
        let importantStyle = SVGSourceStyleElement()
        try? normalStyle.set(attributeDict: normal)
        try? importantStyle.set(attributeDict: important)
        return Declarations(normal: normalStyle, important: importantStyle,
                            rawNormal: rawNormal, rawImportant: rawImportant)
    }

    // MARK: - Matching and the cascade

    /// The declarations of every rule matching `object`, normal priority only.
    func selectorStyle(for object: SVGObject) -> SVGSourceStyleElement {
        var style = SVGSourceStyleElement()
        for rule in matchedRules(for: object) {
            style = style.combine(child: rule.declarations.normal)
        }
        return style
    }

    /// The `!important` declarations of every rule matching `object` (applied after every normal
    /// declaration, including the inline style).
    func importantSelectorStyle(for object: SVGObject) -> SVGSourceStyleElement {
        var style = SVGSourceStyleElement()
        for rule in importantMatchedRules(for: object) {
            style = style.combine(child: rule.declarations.important)
        }
        return style
    }

    /// The `animation`/`animation-*` declarations of the normal rules matching `object`, in
    /// cascade order.
    func animationDeclarations(for object: SVGObject) -> [(property: String, value: String)] {
        return matchedRules(for: object).flatMap { rule in
            rule.declarations.rawNormal.filter {
                $0.property == "animation" || $0.property.hasPrefix("animation-")
            }
        }
    }

    /// The `animation`/`animation-*` declarations of the `!important` rules matching `object`.
    func importantAnimationDeclarations(for object: SVGObject) -> [(property: String, value: String)] {
        return importantMatchedRules(for: object).flatMap { rule in
            rule.declarations.rawImportant.filter {
                $0.property == "animation" || $0.property.hasPrefix("animation-")
            }
        }
    }

    func keyframes(named name: String) -> Keyframes? {
        return keyframes[name]
    }

    /// Matched rules in application order: specificity, then source order.
    private func matchedRules(for object: SVGObject) -> [Rule] {
        let chain = SVGStyleSheet.ancestorChain(of: object)
        return rules
            .filter { SVGStyleSheet.matches($0.selector, chain: chain) }
            .sorted { left, right in
                let a = left.selector.specificity
                let b = right.selector.specificity
                if a != b { return a < b }
                return left.order < right.order
            }
    }

    /// The matched `!important` rules in application order.
    private func importantMatchedRules(for object: SVGObject) -> [Rule] {
        let chain = SVGStyleSheet.ancestorChain(of: object)
        return rules
            .filter { rule in
                !rule.declarations.rawImportant.isEmpty && SVGStyleSheet.matches(rule.selector, chain: chain)
            }
            .sorted { left, right in
                let a = left.selector.specificity
                let b = right.selector.specificity
                if a != b { return a < b }
                return left.order < right.order
            }
    }

    // MARK: - Ancestor chain

    /// The object and its ancestors, nearest first, for descendant-selector matching.
    private static func ancestorChain(of object: SVGObject) -> [SVGObject] {
        var chain: [SVGObject] = [object]
        var current: AnyObject = object
        while true {
            let next: AnyObject
            if let child = current as? SVGChildObject {
                next = child.parent
            } else if let shape = current as? SVGShapeObject {
                next = shape.parent
            } else if let use = current as? SVGUseTag {
                next = use.parent
            } else if let image = current as? SVGImage {
                next = image.parent
            } else {
                break
            }
            guard let ancestor = next as? SVGObject else { break }
            chain.append(ancestor)
            current = ancestor
        }
        return chain
    }

    private static func matches(_ selector: Selector, chain: [SVGObject]) -> Bool {
        guard let subject = selector.compounds.last, subject.matches(chain[0]) else { return false }
        var ancestorIndex = 1
        var compoundIndex = selector.compounds.count - 2
        while compoundIndex >= 0 {
            var matched = false
            while ancestorIndex < chain.count {
                if selector.compounds[compoundIndex].matches(chain[ancestorIndex]) {
                    matched = true
                    ancestorIndex += 1
                    break
                }
                ancestorIndex += 1
            }
            if !matched { return false }
            compoundIndex -= 1
        }
        return true
    }

    // MARK: - CSS text helpers

    private struct Block {
        let prelude: String
        let body: String
    }

    /// Splits CSS text into `(prelude, body)` blocks at the top level.
    private static func blocks(in text: String) -> [Block] {
        var result: [Block] = []
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            var prelude = ""
            while i < chars.count, chars[i] != "{" {
                prelude.append(chars[i])
                i += 1
            }
            guard i < chars.count else { break }
            i += 1 // consume '{'
            var name = SVGUtils.trimmed(string: prelude)
            // A statement at-rule ends at its last ';': the rest of the prelude is this block's
            // own selector, not part of the at-rule.
            if name.hasPrefix("@"), let semicolon = name.lastIndex(of: ";") {
                name = SVGUtils.trimmed(string: String(name[name.index(after: semicolon)...]))
            }
            if name.isEmpty {
                var depth = 1
                while i < chars.count, depth > 0 {
                    if chars[i] == "{" { depth += 1 }
                    else if chars[i] == "}" { depth -= 1 }
                    i += 1
                }
                continue
            }
            if name.hasPrefix("@") {
                var body = ""
                var depth = 1
                while i < chars.count, depth > 0 {
                    if chars[i] == "{" { depth += 1 }
                    else if chars[i] == "}" { depth -= 1 }
                    if depth > 0 { body.append(chars[i]) }
                    i += 1
                }
                result.append(Block(prelude: name, body: body))
                continue
            }
            var body = ""
            while i < chars.count, chars[i] != "}" {
                body.append(chars[i])
                i += 1
            }
            if i < chars.count { i += 1 } // consume '}'
            result.append(Block(prelude: name, body: body))
        }
        return result
    }

    private static func splitSelectors(_ prelude: String) -> [String] {
        var pieces: [String] = []
        var current = ""
        var depth = 0
        var quote: Character?
        for character in prelude {
            if let q = quote {
                current.append(character)
                if character == q { quote = nil }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                current.append(character)
            } else if character == "(" || character == "[" {
                depth += 1
                current.append(character)
            } else if character == ")" || character == "]" {
                depth = max(0, depth - 1)
                current.append(character)
            } else if character == ",", depth == 0 {
                pieces.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        pieces.append(current)
        return pieces
            .map { SVGUtils.trimmed(string: $0) }
            .filter { !$0.isEmpty }
    }

    /// A selector chain with descendant combinators only; `nil` for everything out of profile.
    private static func parseSelector(_ text: String) -> Selector? {
        let trimmed = SVGUtils.trimmed(string: text)
        guard !trimmed.isEmpty else { return nil }
        for character in trimmed where ">+~:[]()".contains(character) { return nil }
        var compounds: [Compound] = []
        for token in trimmed.split(whereSeparator: { $0.isWhitespace }) {
            guard let compound = parseCompound(String(token)) else { return nil }
            compounds.append(compound)
        }
        return compounds.isEmpty ? nil : Selector(compounds: compounds)
    }

    private static func parseCompound(_ token: String) -> Compound? {
        var tag: String?
        var classes: [String] = []
        var id: String?
        let characters = Array(token)
        var i = 0
        var universal = false
        if i < characters.count, characters[i] == "*" {
            universal = true
            i += 1
        } else {
            var name = ""
            while i < characters.count,
                  characters[i].isLetter || characters[i].isNumber
                    || characters[i] == "-" || characters[i] == "_" {
                name.append(characters[i])
                i += 1
            }
            if !name.isEmpty {
                guard name.first?.isLetter == true || name.first == "_" else { return nil }
                tag = name
            }
        }
        while i < characters.count {
            let marker = characters[i]
            guard marker == "." || marker == "#" else { return nil }
            i += 1
            var name = ""
            while i < characters.count,
                  characters[i].isLetter || characters[i].isNumber
                    || characters[i] == "-" || characters[i] == "_" {
                name.append(characters[i])
                i += 1
            }
            guard !name.isEmpty else { return nil }
            if marker == "." {
                classes.append("." + name)
            } else {
                guard id == nil else { return nil }
                id = "#" + name
            }
        }
        if !universal && tag == nil && classes.isEmpty && id == nil { return nil }
        return Compound(tag: tag, classes: classes, id: id)
    }

    private static func keyframeOffsets(_ prelude: String) -> [Double] {
        var offsets: [Double] = []
        for raw in prelude.split(separator: ",") {
            let token = SVGUtils.trimmed(string: String(raw)).lowercased()
            if token == "from" {
                offsets.append(0)
            } else if token == "to" {
                offsets.append(1)
            } else if token.hasSuffix("%"), let percent = Double(token.dropLast()) {
                offsets.append(percent / 100)
            } else {
                return [] // an invalid keyframe selector drops the whole block, as CSS does
            }
        }
        return offsets
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
}
