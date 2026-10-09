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
            targets: ["SVGRenderKit"])
    ],
    targets: [
        .target(
            name: "SVGRenderKit",
            path: "Sources/SVGRenderKit"),
        .testTarget(
            name: "SVGRenderKitTests",
            dependencies: ["SVGRenderKit"],
            path: "Tests/SVGRenderKitTests")
    ]
)
