// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AETHER",
    platforms: [.macOS(.v15)],
    products: [
        // A droplet is a loadable bundle, so its product is a dynamic library.
        // Do not statically bundle DroppyKit; Droppy provides DroppyKit.framework at load time.
        .library(name: "AETHER", type: .dynamic, targets: ["AETHER"])
    ],
    dependencies: [
        // Matches kit.minAPI in droplet.json so compatibility bounds stay synchronized.
        .package(url: "https://gitlab.com/droppyformac1/droppykit.git", from: "1.23.0")
    ],
    targets: [
        .target(
            name: "CodeCatchCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "AetherEngine",
            dependencies: ["CodeCatchCore"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(
            name: "AetherIPC",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "AETHER",
            dependencies: [
                "CodeCatchCore",
                "AetherEngine",
                "AetherIPC",
                .product(name: "DroppyKit", package: "droppykit"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "AETHERHarness",
            dependencies: [
                "AETHER",
                .product(name: "DroppyKitHarness", package: "droppykit"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
