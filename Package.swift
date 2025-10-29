// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "DswAggregator",
    platforms: [
       .macOS(.v13)
    ],
    dependencies: [
        // 💧 A server-side Swift web framework.
        .package(url: "https://github.com/vapor/vapor.git", from: "4.115.0"),
        // 🔵 Non-blocking, event-driven networking for Swift. Used for custom executors
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.4")
    ],
    targets: [
        // Shared library with common code (models, services, parsers, etc.)
        .target(
            name: "DswCore",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                "SwiftSoup"
            ],
            path: "Sources/DswAggregator",
            swiftSettings: swiftSettings
        ),
        // Main API server
        .executableTarget(
            name: "DswAggregator",
            dependencies: [
                "DswCore",
                .product(name: "Vapor", package: "vapor"),
            ],
            path: "Sources/App",
            swiftSettings: swiftSettings
        ),
        // Sync runner for Firestore data preloading
        .executableTarget(
            name: "SyncRunner",
            dependencies: [
                "DswCore",
                .product(name: "Vapor", package: "vapor"),
            ],
            path: "Sources/SyncRunner",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "DswAggregatorTests",
            dependencies: [
                "DswCore",
                .product(name: "VaporTesting", package: "vapor"),
            ],
            swiftSettings: swiftSettings
        )
    ]
)

var swiftSettings: [SwiftSetting] { [
    .enableUpcomingFeature("ExistentialAny"),
] }
