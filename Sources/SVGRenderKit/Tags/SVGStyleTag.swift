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
        var stylesDict: [String: String] = [:]
        var key: String = ""
        var value: String = ""
        var isValue: Bool = false
        for char in styleStr {
            if char == "{" {
                isValue = true
            } else if char == "}" {
                isValue = false
                stylesDict[SVGUtils.trimmed(string: key)] = SVGUtils.trimmed(string: value)
                key = ""
                value = ""
            } else {
                if isValue == true {
                    value.append(char)
                } else {
                    key.append(char)
                }
            }
        }

        for style in stylesDict {
            let key: String = style.key
            let keys = key.split(separator: ",").map { String($0) }
            try keys.forEach { (_key) in
                let key = _key.removeSpaces()
                if key.hasPrefix(".") && key.count > 1 {
                    if let element = self.byClassDict[key] {
                        try element.set(styleStr: style.value, force: true)
                    } else {
                        let element = SVGSourceStyleElement()
                        try element.set(styleStr: style.value, force: true)
                        self.byClassDict[key] = element
                    }
                } else if key.hasPrefix("#") && key.count > 1 {
                    if let element = self.byIdDict[key] {
                        try element.set(styleStr: style.value, force: true)
                    } else {
                        let element = SVGSourceStyleElement()
                        try element.set(styleStr: style.value, force: true)
                        self.byIdDict[key] = element
                    }
                } else if key.count > 0 {
                    if let element = self.byTagDict[key] {
                        try element.set(styleStr: style.value, force: true)
                    } else {
                        let element = SVGSourceStyleElement()
                        try element.set(styleStr: style.value, force: true)
                        self.byTagDict[key] = element
                    }
                }
            }
        }
    }
}
