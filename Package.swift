// swift-tools-version: 6.0
import PackageDescription

// The same model files are tested on macOS when the iOS simulator is unavailable.
let package = Package(
    name: "IurubCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "IurubCore", targets: ["IurubCore"])],
    targets: [
        .target(name: "IurubCore", path: "iurub/Models"),
        .testTarget(name: "IurubCoreTests", dependencies: ["IurubCore"], path: "iurubTests")
    ],
    swiftLanguageModes: [.v5]
)
