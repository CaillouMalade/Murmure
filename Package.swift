// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Murmure",
    platforms: [.macOS("15.0")],
    products: [.executable(name: "Murmure", targets: ["Murmure"])],
    targets: [
        .target(name: "MurmureCore"),
        .executableTarget(name: "Murmure", dependencies: ["MurmureCore"]),
        .testTarget(name: "MurmureCoreTests", dependencies: ["MurmureCore"])
    ]
)
