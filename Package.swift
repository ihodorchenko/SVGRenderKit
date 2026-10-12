// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SVGRenderKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "SVGRenderKit",
            targets: ["SVGRenderKit"]),
        .library(
            name: "SVGRenderKitSwiftUI",
            targets: ["SVGRenderKitSwiftUI"])
    ],
    targets: [
        .target(
            name: "SVGRenderKit",
            path: "Sources/SVGRenderKit"),
        .target(
            name: "SVGRenderKitSwiftUI",
            dependencies: ["SVGRenderKit"],
            path: "Sources/SVGRenderKitSwiftUI"),
        .testTarget(
            name: "SVGRenderKitTests",
            dependencies: ["SVGRenderKit", "SVGRenderKitSwiftUI"],
            path: "Tests/SVGRenderKitTests")
    ],
    swiftLanguageVersions: [.v5, .version("6")]
)
