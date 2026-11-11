// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LittleBro",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LittleBro", targets: ["LittleBro"]),
        .executable(name: "littlebro-render", targets: ["LittleBroRender"]),
    ],
    targets: [
        .target(name: "LittleBroCore"),
        .executableTarget(name: "LittleBro", dependencies: ["LittleBroCore"]),
        .executableTarget(name: "LittleBroRender", dependencies: ["LittleBroCore"]),
        .testTarget(name: "LittleBroCoreTests", dependencies: ["LittleBroCore"]),
    ],
    swiftLanguageModes: [.v5]
)
