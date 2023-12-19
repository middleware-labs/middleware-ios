// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MiddlewareRum",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .tvOS(.v13)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "MiddlewareRum",
            targets: ["MiddlewareRum"]),
    ],
    dependencies: [
        .package(url: "https://github.com/open-telemetry/opentelemetry-swift", from: "1.8.0"),
        .package(url: "https://github.com/devicekit/DeviceKit.git", from: "5.1.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "MiddlewareRum",
            dependencies: [
                .product(name: "OpenTelemetryApi", package: "opentelemetry-swift"),
                .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift"),
                .product(name: "OpenTelemetryProtocolExporterHTTP", package: "opentelemetry-swift"),
                .product(name: "StdoutExporter", package: "opentelemetry-swift"),
                .product(name: "ResourceExtension", package: "opentelemetry-swift"),
                .product(name: "URLSessionInstrumentation", package: "opentelemetry-swift"),
                .product(name: "NetworkStatus", package: "opentelemetry-swift"),
                .product(name: "SignPostIntegration", package: "opentelemetry-swift"),
                .product(name: "DeviceKit", package: "DeviceKit")
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "MiddlewareRumTests",
            dependencies: ["MiddlewareRum"]),
    ]
)