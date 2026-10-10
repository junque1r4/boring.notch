// swift-tools-version: 5.9
// SPDX-License-Identifier: GPL-3.0-only
import PackageDescription

let package = Package(
    name: "AgentMonitorCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "AgentMonitorCore", targets: ["AgentMonitorCore"])],
    targets: [
        .target(name: "AgentMonitorCore", path: "boringNotch/Agents/Core"),
        .testTarget(name: "AgentMonitorCoreTests", dependencies: ["AgentMonitorCore"], path: "Tests/AgentMonitorCoreTests")
    ]
)
