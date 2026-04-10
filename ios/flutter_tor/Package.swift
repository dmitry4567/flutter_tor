// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "flutter_tor",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(name: "flutter-tor", targets: ["flutter_tor"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "flutter_tor",
            dependencies: [],
            resources: []
        )
    ]
)
