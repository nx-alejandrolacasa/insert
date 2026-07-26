// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Insert",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Insert",
            path: "Sources/Insert"
        )
    ]
)
