// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GitWorkbench",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "GitWorkbench", targets: ["GitWorkbench"]),
    ],
    targets: [
        .target(
            name: "GitWorkbench",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "GitWorkbenchTests",
            dependencies: ["GitWorkbench"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
