// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftWebUICore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SwiftWebUICore", targets: ["SwiftWebUICore"])
    ],
    targets: [
        .target(name: "SwiftWebUICore"),
        .testTarget(name: "SwiftWebUICoreTests", dependencies: ["SwiftWebUICore"])
    ]
)
