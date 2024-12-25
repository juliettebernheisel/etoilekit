// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "EtoileKit",
    platforms: [
        .iOS(.v17),
        .macCatalyst(.v17),
        .macOS(.v15),
        .watchOS(.v8),
        .tvOS(.v17),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "EtoileKit",
            targets: ["EtoileKit"]),
        
    ],
    dependencies: [
        .package(url: "https://github.com/hyperoslo/Cache", .upToNextMajor(from: "7.4.0")),
        .package(path: "../jellyfin-sdk-swift"),
        .package(url: "https://github.com/auth0/SimpleKeychain", .upToNextMajor(from: "1.1.0")),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "EtoileKit",
            dependencies: ["Cache", .product(name: "JellyfinAPI", package: "jellyfin-sdk-swift"), "SimpleKeychain"]),
        .testTarget(
            name: "EtoileKitTests",
            dependencies: ["EtoileKit"]
        ),
    ]
)
