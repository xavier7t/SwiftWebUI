// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftWebUICore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SwiftWebUICore", targets: ["SwiftWebUICore"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "604.0.0")
    ],
    targets: [
        .target(
            name: "SwiftWebUICore",
            dependencies: [.product(name: "SwiftSyntax", package: "swift-syntax"),
                           .product(name: "SwiftParser", package: "swift-syntax")]
        ),
        .testTarget(name: "SwiftWebUICoreTests", dependencies: ["SwiftWebUICore"])
    ]
)
