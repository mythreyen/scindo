// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "VolumeDialApp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "VolumeDialApp", targets: ["VolumeDialApp"])
    ],
    targets: [
        .executableTarget(
            name: "VolumeDialApp",
            path: ".",
            exclude: ["Config", "project.yml", "build_and_run.sh", "INSTRUCTIONS.md", "build", "VolumeDialApp.xcodeproj", "Frontend/SWIFT_FRONTEND_GUIDE.md"],
            sources: ["Sources", "Frontend"]
        )
    ]
)
