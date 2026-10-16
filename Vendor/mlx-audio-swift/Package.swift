// swift-tools-version:6.2
// Trimmed copy of Blaizzy/mlx-audio-swift (MIT) — only the Speech-to-Text stack, with ParakeetModel.fromDirectory made public.
import PackageDescription

let package = Package(
    name: "MLXAudio",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MLXAudioSTT", targets: ["MLXAudioSTT"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift.git", .upToNextMajor(from: "0.30.6")),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", .upToNextMajor(from: "3.32.3")),
        .package(url: "https://github.com/huggingface/swift-transformers.git", .upToNextMajor(from: "1.1.6")),
        .package(url: "https://github.com/huggingface/swift-huggingface.git", .upToNextMajor(from: "0.8.1"))
    ],
    targets: [
        .target(
            name: "MLXAudioCore",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
            ],
            path: "Sources/MLXAudioCore",
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-warn-concurrency"], .when(configuration: .debug))
            ]
        ),
        .target(
            name: "MLXAudioCodecs",
            dependencies: [
                "MLXAudioCore",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXFast", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Transformers", package: "swift-transformers"),
            ],
            path: "Sources/MLXAudioCodecs"
        ),
        .target(
            name: "MLXAudioVAD",
            dependencies: [
                "MLXAudioCore",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
            ],
            path: "Sources/MLXAudioVAD",
            exclude: [
                "Models/SileroVAD/README.md",
                "Models/SmartTurn/README.md",
                "Models/Sortformer/README.md",
            ]
        ),
        .target(
            name: "MLXAudioSTT",
            dependencies: [
                "MLXAudioCore",
                "MLXAudioCodecs",
                "MLXAudioVAD",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXFast", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Transformers", package: "swift-transformers"),
            ],
            path: "Sources/MLXAudioSTT",
            exclude: [
                "Models/CohereTranscribe/README.md",
                "Models/FireRedASR2/README.md",
                "Models/GLMASR/README.md",
                "Models/GraniteSpeech/README.md",
                "Models/MossTranscribeDiarize/README.md",
                "Models/NemotronASR/README.md",
                "Models/Parakeet/README.md",
                "Models/Qwen3ASR/README.md",
                "Models/SenseVoice/README.md",
                "Models/VoxtralRealtime/README.md",
                "Models/Whisper/README.md",
            ]
        )
    ]
)
