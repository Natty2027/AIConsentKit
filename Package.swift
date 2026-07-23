// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AIConsentKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "AIConsentKit", targets: ["AIConsentKit"])
    ],
    targets: [
        .target(
            name: "AIConsentKit",
            path: "Sources/AIConsentKit"
        ),
        .testTarget(
            name: "AIConsentKitTests",
            dependencies: ["AIConsentKit"],
            path: "Tests/AIConsentKitTests"
        )
    ]
)
