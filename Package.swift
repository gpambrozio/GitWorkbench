// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GitWorkbench",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "GitWorkbench", targets: ["GitWorkbench"]),
        .executable(name: "GitWorkbenchDemo", targets: ["GitWorkbenchDemo"]),
        .library(name: "GitWorkbenchGitKit", targets: ["GitWorkbenchGitKit"]),
        .executable(name: "GitWorkbenchLiveDemo", targets: ["GitWorkbenchLiveDemo"]),
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
        .target(
            name: "GitWorkbenchGitKit",
            dependencies: ["GitWorkbench"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "GitWorkbenchGitKitTests",
            dependencies: ["GitWorkbenchGitKit", "GitWorkbench"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "GitWorkbenchLiveDemo",
            dependencies: ["GitWorkbench", "GitWorkbenchGitKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
