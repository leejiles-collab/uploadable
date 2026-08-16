// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "fitscli",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../FitsKit")
    ],
    targets: [
        .executableTarget(
            name: "fitscli",
            dependencies: [.product(name: "FitsKit", package: "FitsKit")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
