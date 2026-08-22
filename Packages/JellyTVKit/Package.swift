// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "JellyTVKit",
    platforms: [
        .tvOS(.v17),
        .iOS(.v17),
        .macOS(.v13),
    ],
    products: [
        .library(name: "JellyTVKit", targets: ["JellyTVKit"]),
    ],
    targets: [
        .target(name: "JellyTVKit", resources: [.copy("Resources/MockCatalog")]),
        .executableTarget(name: "MockCatalogGenerator", dependencies: ["JellyTVKit"]),
        .testTarget(name: "JellyTVKitTests", dependencies: ["JellyTVKit"]),
    ]
)
