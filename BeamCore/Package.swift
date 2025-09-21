// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BeamCore",
    platforms: [
        .iOS(.v26)   // iOS-only package
    ],
    products: [
        .library(name: "BeamCore", targets: ["BeamCore"])
    ],
    targets: [
        .target(
            name: "BeamCore",
            path: "Sources/BeamCore"
        )
    ]
)
