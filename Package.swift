// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GitWorkbench",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "GitWorkbench", targets: ["GitWorkbench"]),
        .executable(name: "GitWorkbenchDemo", targets: ["GitWorkbenchDemo"]),
    ],
    targets: [
        .target(
            name: "GitWorkbench",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "GitWorkbenchDemo",
            dependencies: ["GitWorkbench"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "GitWorkbenchTests",
            dependencies: ["GitWorkbench"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
