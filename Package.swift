// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pesty",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Pesty", targets: ["Pesty"])
    ],
    targets: [
        .executableTarget(
            name: "Pesty",
            path: "Sources/Pesty",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .testTarget(
            name: "PestyTests",
            dependencies: ["Pesty"],
            path: "Tests/PestyTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
