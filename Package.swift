// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Grid",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "SMC",
            path: "Sources/SMC",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "Grid",
            dependencies: ["SMC"],
            path: "Sources",
            exclude: ["SMC", "Info.plist"],
            resources: [
                .process("Assets.xcassets")
            ],
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .testTarget(
            name: "GridTests",
            dependencies: ["Grid"],
            path: "Tests"
        )
    ]
)
