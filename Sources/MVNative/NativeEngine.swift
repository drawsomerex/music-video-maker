// On-device Swift-MLX engine: Parakeet word timing and the language model, with model tiers and idle unloading.
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
        public var displayName: String {
            switch self { case .small: return "Qwen3 1.7B"; case .balanced: return "Gemma 4 E2B"; case .best: return "Qwen3.5 9B" }
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

    public static var speechInstalled: Bool { fileSize(speechDir.appendingPathComponent("model.safetensors")) > 50_000_000 }
    static func fileSize(_ u: URL) -> Int { ((try? FileManager.default.attributesOfItem(atPath: u.path))?[.size] as? Int) ?? 0 }
    /// Bytes used by a model folder (for the Settings list).
    public static func sizeOnDisk(_ dir: URL) -> Int {
        (FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey])?.compactMap { ($0 as? URL).flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } }.reduce(0, +)) ?? 0
    }
    public static var speechBytes: Int { sizeOnDisk(speechDir) }
    public static var llmBytes: Int { sizeOnDisk(llmDir) }
    /// "Gemma 4 E2B" etc., read from the note written at download time.
    public static var llmName: String {
        if let n = (try? Data(contentsOf: llmDir.appendingPathComponent(".mv-model.json"))).flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: String] })?["name"] { return n }
        let type = ((try? Data(contentsOf: llmDir.appendingPathComponent("config.json"))).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["model_type"] as? String) ?? ""
        return type.hasPrefix("gemma4") ? "Gemma 4" : (type.hasPrefix("qwen3_5") ? "Qwen3.5" : (type.hasPrefix("qwen3") ? "Qwen3" : "Language model"))
    }
    public static var llmInstalled: Bool { FileManager.default.fileExists(atPath: llmDir.appendingPathComponent("config.json").path) && llmIntact }
    /// False when files recorded at download time are missing or the wrong size (an interrupted or damaged download). Older installs have no record and count as fine.
    static var llmIntact: Bool {
        guard let d = try? Data(contentsOf: llmDir.appendingPathComponent(".mv-manifest.json")), let m = try? JSONSerialization.jsonObject(with: d) as? [String: Int] else {
            // No record (older install): at least require real weight files, not a saved error page.
            let weights = ((try? FileManager.default.contentsOfDirectory(at: llmDir, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "safetensors" }
            return !weights.isEmpty && weights.allSatisfy { fileSize($0) > 20_000_000 }
        }
        return m.allSatisfy { name, size in ((try? FileManager.default.attributesOfItem(atPath: llmDir.appendingPathComponent(name).path))?[.size] as? Int) == size }
    }
    /// Deletes the language model so the setup screen downloads it again (Settings ▸ Repair).
    public static func resetLanguageModel() { try? FileManager.default.removeItem(at: llmDir) }
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
            if container == nil {
                do { container = try await LLMModelFactory.shared.loadContainer(from: NativeEngine.llmDir, using: #huggingFaceTokenizerLoader()) }
                catch { throw MVError("The language model couldn't be opened — its files may be damaged or incomplete. Open Settings ▸ On-device AI and press “Download again” next to the language model.\n\n(Details: \(error.localizedDescription))") }
            }
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
