// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Trim",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Trim",
            path: "Sources/Trim"
        ),
    ]
)
