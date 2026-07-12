// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "parity-harness",
    platforms: [.macOS(.v13)],
    targets: [
        .binaryTarget(
            name: "llama",
            path: "../../NoesisNoema/Frameworks/xcframeworks/llama.xcframework"
        ),
        .executableTarget(
            name: "parity-harness",
            dependencies: ["llama"]
        ),
    ]
)
