// swift-tools-version:6.0
import PackageDescription
import Foundation

// Normal build (`swift build` / ./build_app.sh): talks to oMLX; no MLX libraries are compiled.
// Native build (MV_NATIVE=1, used by install_native.sh through xcodebuild): speech + prompt-writing run inside the app
// with Swift MLX — no oMLX, no Python.
let native = ProcessInfo.processInfo.environment["MV_NATIVE"] != nil

var dependencies: [Package.Dependency] = [
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
]
var nativeDeps: [Target.Dependency] = []
var nativeDefines: [SwiftSetting] = [.swiftLanguageMode(.v5)]
var extraTargets: [Target] = []

if native {
    dependencies += [
        .package(path: "Vendor/mlx-audio-swift"),                      // Parakeet (trimmed MIT copy, see Vendor/README)
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMinor(from: "3.32.3")),
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
    ]
    extraTargets = [
        .target(
            name: "MVNative",
            dependencies: [
                "MVCore",
                .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
    nativeDeps = ["MVNative"]
    nativeDefines.append(.define("NATIVE_MLX"))
}

let package = Package(
    name: "MusicVideo",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "mvideo", targets: ["mvideo"]),
        .executable(name: "MusicVideoApp", targets: ["MusicVideoApp"]),
    ],
    dependencies: dependencies,
    targets: [
        .testTarget(name: "MVCoreTests", dependencies: ["MVCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "MVCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "mvideo", dependencies: ["MVCore", .product(name: "ArgumentParser", package: "swift-argument-parser")] + nativeDeps, swiftSettings: nativeDefines),
        .executableTarget(name: "MusicVideoApp", dependencies: ["MVCore"] + nativeDeps, swiftSettings: nativeDefines),
    ] + extraTargets
)
