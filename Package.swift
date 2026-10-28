// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Murmure",
    platforms: [.macOS("15.0")],
    products: [.executable(name: "Murmure", targets: ["Murmure"])],
    targets: [
        .target(name: "MurmureCore"),
        .target(name: "MurmureUI"),
        .executableTarget(name: "Murmure", dependencies: ["MurmureCore", "MurmureUI"]),
        .testTarget(name: "MurmureCoreTests", dependencies: ["MurmureCore"]),
        .testTarget(name: "MurmureUITests", dependencies: ["MurmureUI"])
    ]
)
