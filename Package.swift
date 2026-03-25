// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "UFCSwap",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "UFCSwap", targets: ["UFCSwap"])
    ],
    targets: [
        .executableTarget(
            name: "UFCSwap",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
