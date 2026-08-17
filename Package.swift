// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Insert",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Insert",
            path: "Sources/Insert",
            // The two bundled OFL faces (see BundledFonts). Declared as a
            // SwiftPM resource rather than dropped into Resources/ beside
            // Info.plist so `Bundle.module` finds them in **both** the assembled
            // app and `swift test` — which is what lets TypefaceTests pin the
            // registration, and a bundled face that silently isn't there is
            // exactly the failure that needs pinning. build.sh copies the
            // generated Insert_Insert.bundle into the app.
            resources: [.copy("Fonts")]
        ),
        .testTarget(
            name: "InsertTests",
            dependencies: ["Insert"],
            path: "Tests/InsertTests"
        ),
    ]
)
