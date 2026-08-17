// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UploadableKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v14)
    ],
    products: [
        .library(name: "UploadableKit", targets: ["UploadableKit"])
    ],
    targets: [
        .target(
            name: "UploadableKit",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "UploadableKitTests",
            dependencies: ["UploadableKit"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
