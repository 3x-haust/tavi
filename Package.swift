// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tavi",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TaviCore", targets: ["TaviCore"]),
        .executable(name: "Tavi", targets: ["Tavi"]),
    ],
    targets: [
        .target(name: "TaviCore", resources: [.process("Resources")]),
        .executableTarget(
            name: "Tavi", dependencies: ["TaviCore"],
            linkerSettings: [
                .linkedFramework("ApplicationServices"), .linkedFramework("Carbon"),
                .linkedFramework("InputMethodKit"),
            ]
        ),
        .testTarget(name: "TaviCoreTests", dependencies: ["TaviCore"]),
    ],
    swiftLanguageModes: [.v5]
)
