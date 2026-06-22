// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BrowserSessions",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "BrowserSessions", targets: ["BrowserSessions"]),
        .executable(name: "BrowserSessionsTestRunner", targets: ["BrowserSessionsTestRunner"]),
    ],
    targets: [
        .target(
            name: "BrowserSessionsCore",
            path: "Sources/BrowserSessionsCore"
        ),
        .executableTarget(
            name: "BrowserSessions",
            dependencies: ["BrowserSessionsCore"],
            path: "Sources/BrowserSessions"
        ),
        .executableTarget(
            name: "BrowserSessionsTestRunner",
            dependencies: ["BrowserSessionsCore"],
            path: "Tests/BrowserSessionsTestRunner"
        ),
    ]
)
