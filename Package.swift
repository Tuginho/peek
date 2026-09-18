// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Peek",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "PeekKit",
            path: "Sources/PeekKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Peek",
            dependencies: ["PeekKit"],
            path: "Sources/Peek",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PeekKitTests",
            dependencies: ["PeekKit"],
            path: "Tests/PeekKitTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
