// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Inviso",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "Inviso",
            targets: ["Inviso"]),
    ],
    dependencies: [
        .package(url: "https://github.com/stasel/WebRTC.git", from: "125.6422.1")
    ],
    targets: [
        .target(
            name: "Inviso",
            dependencies: [
                .product(name: "WebRTC", package: "WebRTC")
            ]),
    ]
)
