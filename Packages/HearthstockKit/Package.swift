// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HearthstockKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "HearthstockCore", targets: ["HearthstockCore"]),
        .library(name: "HearthstockStore", targets: ["HearthstockStore"]),
        .library(name: "HearthstockLookup", targets: ["HearthstockLookup"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(name: "HearthstockCore", resources: [.process("Resources")]),
        .target(
            name: "HearthstockStore",
            dependencies: [
                "HearthstockCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        // The only target that uses the network (Open Food Facts).
        .target(name: "HearthstockLookup", dependencies: ["HearthstockCore"]),
        .testTarget(
            name: "HearthstockCoreTests",
            dependencies: ["HearthstockCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "HearthstockStoreTests", dependencies: ["HearthstockStore", "HearthstockCore"]),
        .testTarget(name: "HearthstockLookupTests", dependencies: ["HearthstockLookup", "HearthstockCore"]),
    ]
)
