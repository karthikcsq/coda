// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "Coda", platforms: [.macOS(.v15)],
    products: [.executable(name: "Coda", targets: ["Coda"]), .library(name: "CodaCore", targets: ["CodaCore"])],
    dependencies: [.package(url: "https://github.com/Desert-Ant-Labs/desert-ant-core.git", exact: "4.1.0"), .package(url: "https://github.com/apple/swift-numerics", exact: "1.1.1"), .package(path: "Vendor/KeyboardShortcuts")],
    targets: [
        .target(name: "CodaCore"),
        .target(name: "CodaWho", dependencies: [.product(name: "DesertAnt", package: "desert-ant-core"), .product(name: "AudioIO", package: "desert-ant-core"), .product(name: "RealModule", package: "swift-numerics")], path: "Vendor/Who", exclude: ["LICENSE.md", "CODA-PATCH.md"]),
        .executableTarget(name: "Coda", dependencies: ["CodaCore", "CodaWho", .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"), .product(name: "Voz", package: "desert-ant-core")]),
        .testTarget(name: "CodaCoreTests", dependencies: ["CodaCore"]),
        .testTarget(name: "CodaUITests", dependencies: ["Coda", "CodaCore"]),
        .testTarget(name: "CodaWhoTests", dependencies: ["CodaWho"])
    ]
)
