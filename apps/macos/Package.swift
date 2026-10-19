// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sorcerer",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "Sorcerer", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(
            name: "SorcererTests",
            dependencies: ["Sorcerer"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
