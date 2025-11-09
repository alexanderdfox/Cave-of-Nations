// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CaveOfNations",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CaveOfNations", targets: ["CaveOfNationsApp"])
    ],
    dependencies: [
    ],
    targets: [
        .executableTarget(
            name: "CaveOfNationsApp",
            dependencies: [],
            path: "Sources/CaveOfNationsApp",
            resources: [
                .copy("Resources")
            ]
        )
    ]
)
