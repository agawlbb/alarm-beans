// swift-tools-version: 6.0
// SPDX-License-Identifier: MPL-2.0
import PackageDescription

let package = Package(
    name: "AlarmCore",
    platforms: [.iOS("26.0"), .watchOS("26.0"), .macOS(.v15)],
    products: [.library(name: "AlarmCore", targets: ["AlarmCore"])],
    targets: [
        .target(name: "AlarmCore"),
        .testTarget(name: "AlarmCoreTests", dependencies: ["AlarmCore"])
    ]
)

