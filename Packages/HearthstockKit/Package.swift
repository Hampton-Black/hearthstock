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
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(name: "HearthstockCore"),
        .target(
            name: "HearthstockStore",
            dependencies: [
                "HearthstockCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(name: "HearthstockCoreTests", dependencies: ["HearthstockCore"]),
        .testTarget(name: "HearthstockStoreTests", dependencies: ["HearthstockStore"]),
    ]
)
