// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "middleware-ios",
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
        .package(url:"https://github.com/microsoft/plcrashreporter", from: "1.8.0"),
        .package(url: "https://github.com/devicekit/DeviceKit.git", from: "5.1.0"),
        .package(url: "https://github.com/tsolomko/SWCompression.git", .upToNextMajor(from: "4.8.5")),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.27.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "MiddlewareRum",
            dependencies: [
                .product(name: "CrashReporter", package: "PLCrashReporter"),
                .product(name: "DeviceKit", package: "DeviceKit", condition: .when(platforms: [.iOS, .tvOS, .watchOS, .macCatalyst])),
                .product(name: "SWCompression", package: "SWCompression"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "MiddlewareRumTests",
            dependencies: [
                "MiddlewareRum",
                .product(name: "CrashReporter", package: "PLCrashReporter"),
            ]),
    ]
)
