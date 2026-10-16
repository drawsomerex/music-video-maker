import Foundation
import MVCore
import MLX
import MLXNN
import MLXAudioSTT
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers

/// Swift-MLX speech + language engine that lives inside the app. Models are kept in
/// ~/Library/Application Support/MusicVideo/models, written once by `setup`.
public enum NativeEngine {
    public enum Tier: String, CaseIterable, Sendable {
        case small, balanced, best
        public var llmRepo: String {
            switch self {
            case .small: return "mlx-community/Qwen3-1.7B-4bit"
            case .balanced: return "mlx-community/gemma-4-e2b-it-4bit"
            case .best: return "mlx-community/Qwen3.5-9B-MLX-4bit"
            }
        }
        public var approxGB: Double { self == .small ? 1.0 : (self == .balanced ? 3.6 : 6.0) }
    }

    public static let speechRepo = "selcukkubur/parakeet-ultra-mlx"     // CC-BY-4.0, moondream/parakeet-ultra converted for MLX
    public static var home: URL {
        let u = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MusicVideo/models")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true); return u
    }
    public static var speechDir: URL { home.appendingPathComponent("parakeet-ultra-4bit") }
    public static var llmDir: URL { home.appendingPathComponent("language-model") }

    public static var speechInstalled: Bool { FileManager.default.fileExists(atPath: speechDir.appendingPathComponent("model.safetensors").path) }
    public static var llmInstalled: Bool { FileManager.default.fileExists(atPath: llmDir.appendingPathComponent("config.json").path) }
    public static var isInstalled: Bool { speechInstalled && llmInstalled }

    /// Wires the engine into the core. Call once at launch (native builds only).
    public static func register() {
        NativeHooks.wordTimes = { try await wordTimes(audioPath: $0) }
        NativeHooks.chat = { try await LLMStore.shared.respond(prompt: $0, maxTokens: $1) }
        NativeHooks.isReady = { isInstalled ? nil : "The on-device models aren't installed yet. Run “mvideo setup-native” (or the install script) once." }
    }

    // MARK: Speech

    static func wordTimes(audioPath: String) async throws -> [TimedWord] {
        guard speechInstalled else { throw MVError("The speech model isn't installed yet. Run the install script once.") }
        let pcm = try await Transcriber.loadMono16k(path: audioPath)
        let floats = pcm.map { Float($0) / 32768 }
        return try await Task.detached(priority: .userInitiated) {
            let model = try ParakeetModel.fromDirectory(speechDir)
            let res = model.alignedResult(audio: MLXArray(floats), chunkDuration: 120)
            var words: [TimedWord] = []
            for s in res.sentences { for t in s.tokens {
                if words.isEmpty || t.text.hasPrefix(" ") { words.append(TimedWord(text: t.text.trimmingCharacters(in: .whitespaces), start: t.start, end: t.end)) }
                else { words[words.count - 1].text += t.text; words[words.count - 1].end = t.end }
            } }
            MLX.Memory.clearCache()
            return words.filter { !$0.text.isEmpty }
        }.value
    }

    // MARK: Language model (prompts, descriptions, upload text)

    actor LLMStore {
        static let shared = LLMStore()
        private var container: ModelContainer?
        private var idle: Task<Void, Never>?

        func respond(prompt: String, maxTokens: Int) async throws -> String {
            guard NativeEngine.llmInstalled else { throw MVError("The language model isn't installed yet. Run the install script once.") }
            idle?.cancel()
            if container == nil { container = try await LLMModelFactory.shared.loadContainer(from: NativeEngine.llmDir, using: #huggingFaceTokenizerLoader()) }
            let session = ChatSession(container!, generateParameters: GenerateParameters(maxTokens: maxTokens, temperature: 0.2),
                                      additionalContext: ["enable_thinking": false])
            var text = try await session.respond(to: prompt)
            if let r = text.range(of: "</think>") { text = String(text[r.upperBound...]) }     // drop any reasoning block
            // Free the model's memory a minute after the last request so rendering gets the RAM back.
            idle = Task { try? await Task.sleep(nanoseconds: 60_000_000_000); if !Task.isCancelled { release() } }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func release() { container = nil; MLX.Memory.clearCache() }
    }
}
