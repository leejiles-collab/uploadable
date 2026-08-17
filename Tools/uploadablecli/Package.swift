// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "uploadablecli",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../UploadableKit")
    ],
    targets: [
        .executableTarget(
            name: "uploadablecli",
            dependencies: [.product(name: "UploadableKit", package: "UploadableKit")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
