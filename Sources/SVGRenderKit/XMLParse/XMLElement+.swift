import Foundation

extension XMLElement {
    func attributesDict() -> [String: String] {
        self.allAttributes.mapValues { $0.text }
    }
}
