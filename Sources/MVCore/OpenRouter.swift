// OpenRouter client for generating 16:9 Medium images with openai/gpt-image-2.5-sunburst and checking account credits.
import Foundation

public enum OpenRouter {
    public static let imageModel = "openai/gpt-image-2.5-sunburst"
    public static let aspectRatio = "16:9"
    public static let quality = "medium"

    /// Default estimated cost in USD for one 16:9 Medium image from `openai/gpt-image-2.5-sunburst` (~1,584 image output tokens @ $30/1M + ~100 text input tokens @ $5/1M ≈ $0.048).
    public static let defaultEstimatedCostPerImage: Double = 0.048

    public struct CreditStatus: Sendable, Equatable {
        public var remainingUSD: Double
        public var totalCreditsUSD: Double?
        public var totalUsageUSD: Double?
        public var remaining: Double { remainingUSD }
        public var totalCredits: Double { totalCreditsUSD ?? remainingUSD }
        public var totalUsage: Double { totalUsageUSD ?? 0 }
        public init(remainingUSD: Double, totalCreditsUSD: Double? = nil, totalUsageUSD: Double? = nil) {
            self.remainingUSD = remainingUSD
            self.totalCreditsUSD = totalCreditsUSD
            self.totalUsageUSD = totalUsageUSD
        }
    }

    public struct GeneratedImage: Sendable {
        public var data: Data
        public var fileExtension: String
        public var costUSD: Double
        public var remainingCreditsUSD: Double?
        public var creditsRemaining: Double? { remainingCreditsUSD }
    }

    public static func formatUSD(_ amount: Double) -> String {
        if amount == 0 { return "$0.00" }
        if amount < 0.01 { return String(format: "$%.4f", amount) }
        if amount < 1.0 { return String(format: "$%.3f", amount) }
        return String(format: "$%.2f", amount)
    }

    public static func formatCredits(_ amount: Double) -> String {
        String(format: "$%.2f", amount)
    }

    /// Queries OpenRouter's `/api/v1/credits` and `/api/v1/key` endpoints to determine remaining credits in USD.
    public static func fetchCredits(apiKey: String) async throws -> CreditStatus {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw MVError("Enter your OpenRouter API key first.") }

        var creditsRemaining: Double? = nil
        var totalCredits: Double? = nil
        var totalUsage: Double? = nil

        // 1) Try GET /api/v1/credits (account-wide total_credits and total_usage)
        if let url = URL(string: "https://openrouter.ai/api/v1/credits") {
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.timeoutInterval = 15
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let d = json["data"] as? [String: Any] {
                if let tc = (d["total_credits"] as? NSNumber)?.doubleValue,
                   let tu = (d["total_usage"] as? NSNumber)?.doubleValue {
                    totalCredits = tc
                    totalUsage = tu
                    creditsRemaining = max(0, tc - tu)
                }
            }
        }

        // 2) Also check GET /api/v1/key (key-level limit_remaining and usage, or auth verification)
        if let url = URL(string: "https://openrouter.ai/api/v1/key") {
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.timeoutInterval = 15
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 401 || http.statusCode == 403 {
                throw MVError("OpenRouter rejected that API key (HTTP \(http.statusCode)). Check your key in Settings.")
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let d = json["data"] as? [String: Any] {
                if let limRem = (d["limit_remaining"] as? NSNumber)?.doubleValue {
                    if let cur = creditsRemaining {
                        creditsRemaining = min(cur, max(0, limRem))
                    } else {
                        creditsRemaining = max(0, limRem)
                    }
                }
                if totalUsage == nil, let u = (d["usage"] as? NSNumber)?.doubleValue {
                    totalUsage = u
                }
            }
        }

        if let rem = creditsRemaining {
            return CreditStatus(remainingUSD: rem, totalCreditsUSD: totalCredits, totalUsageUSD: totalUsage)
        }
        throw MVError("Connected to OpenRouter, but couldn't read credit balance from this API key.")
    }

    /// Generates a single 16:9 Medium image using `openai/gpt-image-2.5-sunburst` via OpenRouter.
    /// `scene`: the user's own words for this picture; the prompt is checked against it first (the scene wins over any contradiction). nil = no check.
    public static func generateImage(prompt promptIn: String, apiKey: String, fallbackCostEstimate: Double = defaultEstimatedCostPerImage, referenceJPEGs: [Data] = [], scene: String? = nil) async throws -> GeneratedImage {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw MVError("Enter your OpenRouter API key first to generate images.") }
        var prompt = promptIn
        if let sc = scene { prompt = await PromptCheck.fix(promptIn, scene: sc, kind: .picture, apiKey: key) }

        let preCredits = try? await fetchCredits(apiKey: key)

        var req = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/images")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 180
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("https://github.com/drawsomerex/music-video-maker", forHTTPHeaderField: "HTTP-Referer")
        req.setValue("Music Video Maker", forHTTPHeaderField: "X-Title")

        var payload: [String: Any] = [
            "model": imageModel,
            "prompt": StylePreset.withDetail(prompt),
            "aspect_ratio": aspectRatio,
            "quality": quality
        ]
        // the style guide picture: sent as a reference so the new picture matches its look (adds about half a cent)
        if !referenceJPEGs.isEmpty { payload["input_references"] = referenceJPEGs.map { ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64," + $0.base64EncodedString()]] } }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0

        if !(200..<300).contains(status) {
            let errBody = String(data: data, encoding: .utf8) ?? "HTTP \(status)"
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errObj = json["error"] as? [String: Any],
               let msg = errObj["message"] as? String {
                throw MVError("OpenRouter (\(imageModel)): \(msg)")
            }
            throw MVError("OpenRouter image generation failed (HTTP \(status)): \(errBody.prefix(240))")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MVError("OpenRouter returned an unreadable response.")
        }

        // Extract image bytes and media type from `data[0]`
        var imageBytes: Data? = nil
        var ext = "png"

        if let items = json["data"] as? [[String: Any]], let first = items.first {
            if let mediaType = first["media_type"] as? String {
                if mediaType.contains("jpeg") || mediaType.contains("jpg") { ext = "jpg" }
                else if mediaType.contains("webp") { ext = "webp" }
            }
            if let b64 = first["b64_json"] as? String {
                imageBytes = decodeBase64Image(b64, ext: &ext)
            } else if let urlStr = first["url"] as? String {
                if urlStr.hasPrefix("data:") {
                    imageBytes = decodeBase64Image(urlStr, ext: &ext)
                } else if let imgURL = URL(string: urlStr) {
                    let (dl, _) = try await URLSession.shared.data(from: imgURL)
                    imageBytes = dl
                }
            }
        }

        guard let validBytes = imageBytes, !validBytes.isEmpty else {
            throw MVError("OpenRouter didn't return image data in its response.")
        }

        // Extract exact USD cost from `usage.cost` (or token usage / credit delta)
        var reportedCost: Double? = nil
        if let usage = json["usage"] as? [String: Any] {
            if let c = (usage["cost"] as? NSNumber)?.doubleValue, c > 0 {
                reportedCost = c
            } else if let c = (usage["total_cost"] as? NSNumber)?.doubleValue, c > 0 {
                reportedCost = c
            } else {
                let pTok = (usage["prompt_tokens"] as? NSNumber)?.doubleValue ?? 0
                let cTok = (usage["completion_tokens"] as? NSNumber)?.doubleValue ?? 0
                if pTok > 0 || cTok > 0 {
                    // openai/gpt-image-2.5-sunburst endpoint pricing: $5/1M input text, $30/1M output image tokens
                    let computed = pTok * 0.000005 + cTok * 0.00003
                    if computed > 0 { reportedCost = computed }
                }
            }
        }

        let postCredits = try? await fetchCredits(apiKey: key)
        if reportedCost == nil,
           let preU = preCredits?.totalUsageUSD,
           let postU = postCredits?.totalUsageUSD,
           postU > preU {
            reportedCost = postU - preU
        }

        let finalCost = max(0.0001, reportedCost ?? fallbackCostEstimate)
        return GeneratedImage(
            data: validBytes,
            fileExtension: ext,
            costUSD: finalCost,
            remainingCreditsUSD: postCredits?.remainingUSD
        )
    }

    private static func decodeBase64Image(_ str: String, ext: inout String) -> Data? {
        var clean = str.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("data:"), let comma = clean.firstIndex(of: ",") {
            let header = String(clean[..<comma])
            if header.contains("jpeg") || header.contains("jpg") { ext = "jpg" }
            else if header.contains("webp") { ext = "webp" }
            clean = String(clean[clean.index(after: comma)...])
        }
        return Data(base64Encoded: clean, options: .ignoreUnknownCharacters)
    }
}
