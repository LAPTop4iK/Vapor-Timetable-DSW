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
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.4"),
        // 🗄️ Fluent ORM and PostgreSQL driver
        .package(url: "https://github.com/vapor/fluent.git", from: "4.12.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.10.0")
    ],
    targets: [
        // Shared library with common code
        .target(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                "SwiftSoup"
            ],
            path: "Sources/DswAggregator",
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "DswAggregator",
            dependencies: [
                .target(name: "App")
            ],
            path: "Sources/Run",
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "SyncRunner",
            dependencies: [
                .target(name: "App")
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "DswAggregatorTests",
            dependencies: [
                .target(name: "App"),
                .product(name: "VaporTesting", package: "vapor"),
            ],
            swiftSettings: swiftSettings
        )
    ]
)

var swiftSettings: [SwiftSetting] { [
    .enableUpcomingFeature("ExistentialAny"),
] }
