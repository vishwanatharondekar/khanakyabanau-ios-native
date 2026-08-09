// swift-tools-version: 5.9
import PackageDescription

/// All model, business-logic and networking code lives here rather than in the app
/// target so it can be exercised with `swift test` on any machine with a Swift
/// toolchain — no iOS SDK, no simulator, no Xcode project required.
let package = Package(
    name: "KhanaKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "KhanaKit", targets: ["KhanaKit"]),
    ],
    targets: [
        .target(name: "KhanaKit"),
        .testTarget(name: "KhanaKitTests", dependencies: ["KhanaKit"]),
    ]
)
