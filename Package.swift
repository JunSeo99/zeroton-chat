// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "ZeroVapor",
    platforms: [
        .macOS(.v12)
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/apns.git", .upToNextMajor(from: "3.0.0")),
        .package(url: "https://github.com/vapor/vapor", .upToNextMajor(from: "4.50.0")),
        .package(url: "https://github.com/mongodb/mongodb-vapor", .upToNextMajor(from: "1.1.0")),
        .package(url: "https://github.com/soto-project/soto.git", .upToNextMajor(from: "6.0.0"))
    ],
    targets: [
        .target(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "MongoDBVapor", package: "mongodb-vapor"),
                .product(name: "APNS", package: "apns"),
                .product(name: "SotoS3", package: "soto"),
            ],
            swiftSettings: [
                .unsafeFlags(["-cross-module-optimization"], .when(configuration: .release))
            ]
        ),
        .executableTarget(name: "Run", dependencies: [
            .target(name: "App"),
            .product(name: "MongoDBVapor", package: "mongodb-vapor")
        ]),
        .testTarget(name: "AppTests", dependencies: [
            .target(name: "App"),
            .product(name: "XCTVapor", package: "vapor"),
        ])
    ]
)
