// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FitsKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v14)
    ],
    products: [
        .library(name: "FitsKit", targets: ["FitsKit"])
    ],
    targets: [
        .target(
            name: "FitsKit",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "FitsKitTests",
            dependencies: ["FitsKit"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
