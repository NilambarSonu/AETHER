// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodeCatch",
    platforms: [.macOS(.v15)],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")],
    targets: [
        .target(name: "CodeCatchCore", path: "Droplet/Sources/CodeCatchCore"),
        .target(
            name: "AetherEngine",
            dependencies: ["CodeCatchCore"],
            path: "Droplet/Sources/AetherEngine",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(name: "AetherCore", dependencies: ["CodeCatchCore"]),
        .executableTarget(
            name: "CodeCatch",
            dependencies: ["AetherCore", "CodeCatchCore", .product(name: "Sparkle", package: "Sparkle")],
            // The rpath finds Sparkle.framework in the app bundle (install.sh copies it there).
            linkerSettings: [.linkedLibrary("sqlite3"), .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        // `codecatch` in the bundle; never name a product that, it is `CodeCatch` on a case-insensitive disk.
        .executableTarget(name: "CodeCatchCLI", dependencies: ["AetherCore", "CodeCatchCore"]),
        .testTarget(name: "CodeCatchCoreTests", dependencies: ["CodeCatchCore"], exclude: ["code-samples.txt"]),
        .testTarget(name: "AetherEngineTests", dependencies: ["AetherEngine", "CodeCatchCore"]),
        .testTarget(name: "AetherCoreTests", dependencies: ["AetherCore"]),
        .testTarget(name: "CodeCatchTests", dependencies: ["CodeCatch"]),
    ],
    swiftLanguageModes: [.v5]
)
