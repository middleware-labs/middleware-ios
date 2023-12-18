// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MiddlewareRum",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "MiddlewareRum",
            targets: ["MiddlewareRum"]),
    ],
    dependencies: [
        .package(url: "https://github.com/open-telemetry/opentelemetry-swift", from: "1.8.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "MiddlewareRum",
            dependencies: ["OpenTelemetrySdk"]
        ),
        .testTarget(
            name: "MiddlewareRumTests",
            dependencies: ["MiddlewareRum"]),
    ]
)
