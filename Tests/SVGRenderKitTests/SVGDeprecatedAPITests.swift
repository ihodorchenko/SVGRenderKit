import XCTest
@testable import SVGRenderKit

/// B118 — the misspelled public names keep working as deprecated shims.
@MainActor
final class SVGDeprecatedAPITests: XCTestCase {

    // Calls inside a deprecated function do not warn, so the shims stay covered without noise.
    @available(*, deprecated)
    private func useOldNames() {
        SVGColors.setOvverideColors(colors: ["shim-a": "#ff0000"])
        SVGColors.addOvverideColors(colors: ["shim-b": "#00ff00"])
        SVGColors.setOvverideUIColors(colors: ["shim-c": .blue])
        SVGColors.addOvverideUIColors(colors: ["shim-d": .green])
    }

    @available(*, deprecated)
    private func useOldViewNames(_ view: SVGView) {
        view.set(svgString: "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1 1\"/>", name: nil, fill_colors: nil)
    }

    func testOldColorOverrideNamesStillWork() {
        defer { SVGColors.setOverrideColors(colors: [:]); SVGColors.setOverrideUIColors(colors: [:]) }
        useOldNames()
        XCTAssertEqual(SVGConfiguration.shared.uiColorOverride(byString: "shim-c"), .blue)
        XCTAssertEqual(SVGConfiguration.shared.uiColorOverride(byString: "shim-d"), .green)
    }

    func testNewColorOverrideNamesWork() {
        defer { SVGColors.setOverrideColors(colors: [:]) }
        SVGColors.setOverrideColors(colors: ["#abcdef": "#ff0000"])
        var r: CGFloat = 0
        SVGColors.getColor(string: "#abcdef").getRed(&r, green: nil, blue: nil, alpha: nil)
        XCTAssertEqual(r, 1, accuracy: 0.01)
    }

    func testOldFillColorsParameterStillCompiles() {
        useOldViewNames(SVGView())
    }
}
