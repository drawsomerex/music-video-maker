// Command-line tool: plan, render, short, resync, setup-native and helpers (same engine as the app).
import Foundation
import ArgumentParser
import MVCore
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
#if NATIVE_MLX
import MVNative
#endif

let progressPrinter: ProgressHandler = { phase, p in
    let bar = String(repeating: "█", count: Int(p * 24)) + String(repeating: "░", count: 24 - Int(p * 24))
    FileHandle.standardError.write(Data("\r\u{1B}[K\(bar) \(Int(p * 100))%  \(phase)".utf8))
    if p >= 1 { FileHandle.standardError.write(Data("\n".utf8)) }
}

func t(_ x: Double) -> String { String(format: "%d:%02d", Int(x) / 60, Int(x) % 60) }

@main
struct MVideo: AsyncParsableCommand {
    /// Make sure a headless engine we started never outlives the command.
    static func main() async {
        #if NATIVE_MLX
        NativeEngine.register()
        #endif
        do {
            var command = try parseAsRoot()
            if var c = command as? AsyncParsableCommand { try await c.run() } else { try command.run() }
            OMLXServer.shared.shutdown()
        } catch {
            OMLXServer.shared.shutdown()
            exit(withError: error)
        }
    }

    static let configuration = CommandConfiguration(
        commandName: "mvideo",
        abstract: "Make a lyric music video in two steps: `plan` (sections + image prompts), then `render` (after you load your pictures).",
        subcommands: [Plan.self, SetupNative.self, AlignCheck.self, Resync.self, AddIntro.self, Ideas.self, Render.self, Short.self, Preview.self, Loop.self, Fit.self, Draw.self, YouTube.self, Models.self, Settings.self], defaultSubcommand: Plan.self)

    // MARK: Step 1
    struct Plan: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Step 1 — transcribe & sync the lyrics, split the song into sections, and write an image prompt for each.")
        @Argument(help: "MP3 or WAV file") var audio: String
        @Option(name: .shortAndLong, help: "Song title (intro slide)") var title: String
        @Option(name: .shortAndLong, help: "Optional: a note about the song, or a subtitle for the title card. The description is written from the lyrics automatically.") var subject: String = ""
        @Option(name: .shortAndLong, help: "Text file containing the lyrics, or - for stdin (blank line = new stanza)") var lyrics: String
        @Option(name: .shortAndLong, help: "Output folder (default: next to the audio)") var out: String?
        @Option(help: "Legacy option (accepted for compatibility). Pictures now follow verse and music boundaries.") var every: Double = 15
        @Option(help: "Visual style preset or custom style string (e.g. oil, acrylic, vector, realistic, watercolor, anime, comic, neon)") var style: String = ""
        @Option(help: "Setting and theme every picture must follow, e.g. \"Brightly lit colonial Philadelphia\"") var setting: String = ""
        @Option(help: "oMLX speech model (default parakeet-ultra-mlx)") var sttModel: String?
        @Option(help: "oMLX language model that writes the prompts") var llmModel: String?

        func run() async throws {
            let audioURL = URL(fileURLWithPath: (audio as NSString).expandingTildeInPath)
            let outDir = URL(fileURLWithPath: ((out ?? audioURL.deletingLastPathComponent().path) as NSString).expandingTildeInPath)
            try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
            let text: String
            if lyrics == "-" { text = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self) }
            else { text = try String(contentsOfFile: (lyrics as NSString).expandingTildeInPath, encoding: .utf8) }
            var cfg = Config.load(); if let m = sttModel { cfg.sttModel = m }; if let m = llmModel { cfg.llmModel = m }
            let work = Pipeline.workDir(output: outDir, title: title)
            let resolvedStyle = StylePreset.all.first(where: { $0.id == style.lowercased() || $0.name.lowercased() == style.lowercased() || (style.count >= 3 && !$0.prompt.isEmpty && $0.name.lowercased().contains(style.lowercased())) })?.prompt ?? style
            let plan = try await Pipeline.plan(audioPath: audioURL.path, title: title, subject: subject, lyrics: text, work: work, imageInterval: every, preferredStyle: resolvedStyle, setting: setting, config: cfg, progress: progressPrinter)

            print(String(format: "\nLyrics matched to the audio: %.0f%%   Images needed: %d (title card + %d sections)   Auto-Shorts queued: %d\n", plan.alignmentCoverage * 100, plan.sections.count + 1, plan.sections.count, plan.shorts.count))
            if plan.alignmentCoverage < 0.5 { print("⚠️  Low match — sync may drift. Check that the lyrics are what's actually sung.\n") }
            print("SONG DESCRIPTION (written from the lyrics): \(plan.description)\n")
            print("STYLE (appended to every prompt): \(plan.style)\n")
            for idx in -1..<plan.sections.count {
                let s = idx < 0 ? plan.intro : plan.sections[idx]
                print(String(format: "%02d  %@", idx + 1, idx < 0 ? "Title card" : "\(t(s.start + plan.audioOffset))–\(t(s.end + plan.audioOffset))  (\(Int(s.duration))s)\(s.lineIDs.isEmpty ? "  instrumental" : "")"))
                for l in s.lineIDs { print("      ♪ \(plan.lines[l].text)") }
                if let r = s.repeatOf { print("      ↺ same lyrics as \(String(format: "%02d", r + 1)) — reuse that picture or make a fresh take") }
                print("      ➜ \(s.prompt)\n")
            }
            print("Prompts file : \(Pipeline.promptsURL(work).path)")
            print("Work folder  : \(work.path)")
            print("\nNext: generate the pictures (16:9), name them 00.png, 01.png, … and run:\n  mvideo render \"\(work.path)\" --images <folder with your pictures> --with-shorts")
        }
    }

    struct SetupNative: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "setup-native", abstract: "Native build only: install the on-device speech + language models (one time).")
        @Option(help: "Language-model size: small (~1 GB), balanced (~2.3 GB, default), best (~6 GB)") var tier = "balanced"
        @Option(help: "Copy the Parakeet Ultra files from this folder instead of downloading") var speechFrom: String?
        @Option(help: "Copy the language model from this folder instead of downloading") var llmFrom: String?
        func run() async throws {
            #if NATIVE_MLX
            guard let t = NativeEngine.Tier(rawValue: tier) else { throw ValidationError("--tier must be small, balanced or best") }
            try await NativeEngine.setup(tier: t, speechFrom: speechFrom.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) },
                                         llmFrom: llmFrom.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }, progress: progressPrinter)
            print("✅ Models installed in \(NativeEngine.home.path)")
            #else
            print("This build talks to oMLX. The native (no oMLX, no Python) build is made by install_native.sh.")
            #endif
        }
    }

    /// Benchmark helper: how well do a model's word timings line up with the lyrics, and how far do they differ from a reference run?
    struct AlignCheck: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "align-check", abstract: "Score a transcription (words.json) against a project's lyrics; optionally compare timings with a reference run.", shouldDisplay: false)
        @Argument var words: String
        @Argument(help: "A project folder (uses its lyrics)") var project: String
        @Option(help: "Reference words.json to compare timings against") var ref: String?
        func run() async throws {
            struct W: Codable { var text: String; var start: Double; var end: Double }
            let ws = try JSONDecoder().decode([W].self, from: Data(contentsOf: URL(fileURLWithPath: words))).map { TimedWord(text: $0.text, start: $0.start, end: $0.end) }
            let plan = try Pipeline.loadPlan(URL(fileURLWithPath: (project as NSString).expandingTildeInPath))
            let res = LyricAligner.align(lines: plan.lines.map(\.text), words: ws, songDuration: plan.songDuration)
            var line = String(format: "words=%d coverage=%.1f%%", ws.count, res.coverage * 100)
            if let r = ref {
                let rw = try JSONDecoder().decode([W].self, from: Data(contentsOf: URL(fileURLWithPath: r))).map { TimedWord(text: $0.text, start: $0.start, end: $0.end) }
                let rr = LyricAligner.align(lines: plan.lines.map(\.text), words: rw, songDuration: plan.songDuration)
                // compare the start time the app would use for every lyric word that both runs matched
                var d: [Double] = []
                for (a, b) in zip(res.lines, rr.lines) { for (x, y) in zip(a.words, b.words) { d.append(abs(x.start - y.start)) } }
                d.sort()
                if !d.isEmpty { line += String(format: " | lyric-word start vs reference: median %.0f ms, p90 %.0f ms, p99 %.0f ms, within 80 ms: %.0f%%", d[d.count / 2] * 1000, d[Int(Double(d.count) * 0.9)] * 1000, d[Int(Double(d.count) * 0.99)] * 1000, 100 * Double(d.filter { $0 <= 0.08 }.count) / Double(d.count)) }
            }
            print(line)
        }
    }

    struct Resync: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Re-time an existing project's lyrics with exact word timestamps (keeps pictures, prompts and Shorts).")
        @Argument(help: "The project folder") var project: String
        func run() async throws {
            let w = URL(fileURLWithPath: (project as NSString).expandingTildeInPath)
            var plan = try Pipeline.loadPlan(w)
            let cov = try await Pipeline.resync(plan: &plan, work: w, progress: progressPrinter)
            print(String(format: "✅ Re-synced with exact word timing — %.0f%% of your lyric words matched.", cov * 100))
        }
    }

    struct AddIntro: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "add-intro", abstract: "Older projects: give the music before the first words its own picture slot and prompt.")
        @Argument(help: "The project folder") var project: String
        func run() async throws {
            let w = URL(fileURLWithPath: (project as NSString).expandingTildeInPath)
            var plan = try Pipeline.loadPlan(w)
            guard Pipeline.needsInstrumentalIntro(plan) else { print("Nothing to add — the opening music already has a picture, or the words start right away."); return }
            try await Pipeline.addInstrumentalIntro(plan: &plan, progress: progressPrinter)
            try Pipeline.savePlan(plan, w)
            print("✅ Added a picture slot (section 1) for the music before the first words.")
        }
    }

    struct Ideas: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Print 10 different setting ideas (place, era, mood) written from your lyrics.")
        @Argument(help: "Text file with the lyrics") var lyrics: String
        @Option(name: .shortAndLong, help: "Song title") var title: String = "Untitled"
        func run() async throws {
            let text = try String(contentsOfFile: (lyrics as NSString).expandingTildeInPath, encoding: .utf8)
            let omlx = OMLX(config: .load()); try await omlx.ensureReady()
            for (i, s) in try await PromptWriter(omlx: omlx).suggestSettings(title: title, lyrics: LyricAligner.parse(text).lines).enumerated() { print("\(i + 1). \(s)") }
        }
    }

    // MARK: Step 2
    struct Render: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Step 2 — load or auto-generate your pictures and render the MP4 (and optionally 4–7 ~30s Shorts).")
        @Argument(help: "The “<Title> – work” folder created by `plan`") var work: String
        @Option(help: "Folder of pictures named 00.png (title card), 01.png, 02.png, …") var images: String?
        @Flag(help: "Auto-generate all missing section pictures via OpenRouter (\(OpenRouter.imageModel) 16:9 Medium)") var generateImages = false
        @Flag(help: "Render even if some sections have no picture (those get a colour gradient)") var allowMissing = false
        @Flag(help: "Also automatically generate and render 4–7 ~30-second Shorts broken at natural stanza boundaries") var withShorts = false
        @Option(help: "Caption height for the full video (fraction of frame height from the bottom, 0.04…0.86)") var captionY: Double?
        @Option(help: "Video height: 720, 1080, 1440, 2160") var height = 1080
        @Option var fps = 30
        @Flag(help: "Encode HEVC instead of H.264") var hevc = false

        func run() async throws {
            let w = URL(fileURLWithPath: (work as NSString).expandingTildeInPath)
            var plan = try Pipeline.loadPlan(w)
            let cfg = Config.load()
            if let y = captionY { plan.captionY = y; try Pipeline.savePlan(plan, w) }
            if let folder = images {
                let r = Pipeline.attachFolder(URL(fileURLWithPath: (folder as NSString).expandingTildeInPath), plan: &plan, work: w)
                print("Loaded \(r.loaded.count) picture(s).")
                r.warnings.forEach { print("⚠️  \($0)") }
            }
            if generateImages {
                let toGen = Pipeline.missing(plan)
                for (idx, sec) in toGen.enumerated() {
                    let label = sec < 0 ? "Title card" : String(format: "Picture %02d", sec + 1)
                    print("[\(idx + 1)/\(toGen.count)] Generating \(label) via \(OpenRouter.imageModel) (16:9 Medium)…")
                    let gen = try await Pipeline.generateSectionImage(section: sec, plan: &plan, work: w, config: cfg)
                    print("  ✓ Saved (\(OpenRouter.formatUSD(gen.costUSD))) · Song total: \(OpenRouter.formatUSD(plan.totalGenerationCostUSD))")
                }
            }
            let missing = Pipeline.missing(plan)
            if !missing.isEmpty {
                print("Missing pictures for: " + missing.map { String(format: "%02d", $0 + 1) }.joined(separator: ", "))
                if !allowMissing { throw ValidationError("Load those pictures, pass --generate-images to generate them via OpenRouter, or pass --allow-missing to use gradients. Prompts are in \(Pipeline.promptsURL(w).path)") }
            }
            let mp4 = Pipeline.videoURL(plan: plan, work: w)
            let t0 = Date()
            try await VideoRenderer.render(plan: plan, work: w, output: mp4, settings: VideoSettings(height: height, fps: fps, hevc: hevc), progress: progressPrinter)
            print(String(format: "✅ %@  (%.0fs to render)", mp4.path, Date().timeIntervalSince(t0)))
            if withShorts {
                if plan.shorts.isEmpty {
                    plan.shorts = Pipeline.autoShorts(plan: plan)
                    try Pipeline.savePlan(plan, w)
                }
                for (i, var c) in plan.shorts.enumerated() {
                    if c.hook.isEmpty, let h = await Pipeline.writeHook(plan: plan, clip: c), !h.isEmpty {
                        c.hook = h; plan.shorts[i].hook = h; try? Pipeline.savePlan(plan, w)
                    }
                    let ts = Date()
                    let sOut = try await Pipeline.renderShort(plan: plan, work: w, clip: c, progress: progressPrinter)
                    print(String(format: "✅ Short %d/%d: %@  (%.0fs)", i + 1, plan.shorts.count, sOut.path, Date().timeIntervalSince(ts)))
                }
            }
        }
    }

    // MARK: YouTube Shorts
    struct Short: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Make a vertical YouTube Short (1080×1920) from part of the song. Pick lyric lines with --lines, or exact times with --from/--to.")
        @Argument(help: "The project folder created by `plan`") var project: String
        @Option(help: "Lyric line numbers, e.g. 7-12 (see `mvideo lyrics`-style list printed below with --list)") var lines: String?
        @Option(help: "Start time, e.g. 1:05.5 or 65.5") var from: String?
        @Option(help: "End time (default: 30 s after --from)") var to: String?
        @Option(help: "Length in seconds when only --from is given") var length = 30.0
        @Option(help: "Seconds of music before the first picked line (default 3)") var lead = 3.0
        @Option(help: "Seconds of music after the last picked line (default 3)") var tail = 3.0
        @Option(help: "Nudge the start by this many seconds (e.g. -0.2)") var nudgeStart = 0.0
        @Option(help: "Nudge the end by this many seconds") var nudgeEnd = 0.0
        @Flag(help: "Snap the start/end to the nearest quiet gap between words") var snap = false
        @Option(help: "Name of the file") var name: String?
        @Option(help: "Opening title text (default: the song title)") var hook: String?
        @Option(help: "Motion: calm (default) or punchy") var motion = "calm"
        @Option(help: "End with a fade of this many seconds instead of looping back to the start (e.g. 2 for a slow fade, 0.05 to stop sharply)") var fade: Double?
        @Option(help: "Lyric text style: pill (default), pop, stack, sweep, auto") var text = "pill"
        @Option(help: "Accent colour name: Hot pink (default), Sun yellow, Electric cyan, Lime, Tangerine, Violet, Auto") var accent = "Hot pink"
        @Flag(help: "Gentle zoom pulse on the beat (calm mode)") var pulse = false
        @Option(help: "Caption height: bottom edge of the captions as a fraction of the frame height, 0.04 (low) … 0.86 (high). Default 0.20") var captionY: Double?
        @Option(help: "Closing text, e.g. \"Full song on YouTube ▶\"") var cta: String?
        @Option(help: "Style seed (same seed = same look). Default: random") var seed: UInt64?
        @Flag(help: "Turn off the dynamic style kit (plain lyrics sweep, black fades)") var plain = false
        @Flag(help: "Don't dissolve the end back into the start") var noLoop = false
        @Option(help: "Render N variants with different looks for A/B testing") var variants = 1
        @Flag(help: "Make the WHOLE song as Shorts: one video if it fits in 3:00, otherwise split into the fewest parts under 3:00") var whole = false
        @Flag(help: "Just list the numbered lyric lines with their times") var list = false
        @Flag(help: "Save the clip in the project but don't render") var noRender = false

        func parseTime(_ s: String) throws -> Double {
            let parts = s.split(separator: ":").map(String.init)
            guard let last = Double(parts.last ?? ""), parts.count <= 2 else { throw ValidationError("Bad time “\(s)” (use 65.5 or 1:05.5)") }
            return parts.count == 2 ? (Double(parts[0]) ?? 0) * 60 + last : last
        }

        func run() async throws {
            let w = URL(fileURLWithPath: (project as NSString).expandingTildeInPath)
            var plan = try Pipeline.loadPlan(w)
            if list {
                for (i, l) in plan.lines.enumerated() { print(String(format: "%2d  %@  %@", i + 1, t(l.start) + String(format: ".%d", Int((l.start - Double(Int(l.start))) * 10)), l.text)) }
                return
            }
            var clip: ShortClip
            var wholeParts: [ShortClip] = []
            if whole {
                wholeParts = Pipeline.wholeSongClips(plan: plan); clip = wholeParts[0]; if wholeParts.count > 1 { print("Song is \(Int(plan.songDuration / 60)):\(String(format: "%02d", Int(plan.songDuration) % 60)) — over the 3:00 Short limit, so it's split into \(wholeParts.count) parts.") }
            } else if let r = lines {
                let p = r.split(separator: "-").compactMap { Int($0) }
                guard !p.isEmpty, p.allSatisfy({ $0 >= 1 && $0 <= plan.lines.count }) else { throw ValidationError("--lines must be like 7-12 within 1…\(plan.lines.count)") }
                clip = Pipeline.clip(plan: plan, lines: p[0] - 1, to: (p.count > 1 ? p[1] : p[0]) - 1, name: name, lead: lead, tail: tail)
            } else if let f = from {
                let s = try parseTime(f), e = try to.map(parseTime) ?? (s + length)
                clip = ShortClip(name: name ?? "Short \(f)", start: s, end: e)
            } else { throw ValidationError("Choose --whole for the full song, lyric lines (--lines 7-12) or a start time (--from 1:05, 30 s long by default; add --to for another end). Use --list to see the lines.") }
            if snap { clip.start = Pipeline.snap(clip.start, plan: plan); clip.end = Pipeline.snap(clip.end, plan: plan) }
            clip.start = max(0, clip.start + nudgeStart); clip.end = min(plan.songDuration, clip.end + nudgeEnd)
            guard clip.duration > 2 else { throw ValidationError("That clip is too short.") }
            if !whole && clip.duration > ShortClip.maxDuration { throw ValidationError(String(format: "That clip is %.0f s — a Short can be at most 3:00 (180 s). Shorten it, or use --whole to split the whole song into parts.", clip.duration)) }
            for var clip in (whole ? wholeParts : [clip]) {
                clip.dynamic = !plain; clip.loop = whole ? false : !noLoop
                if let s = seed { clip.styleSeed = s }
                if let c = cta { clip.cta = c }
                clip.captionY = captionY; clip.hook = hook ?? ""; clip.motion = motion; if let f = fade { clip.loop = false; clip.fadeOut = f }; clip.textStyle = text; clip.accent = accent; clip.pulse = pulse
                if let n = name, !whole { clip.name = n }
                if clip.dynamic { print("Title: \(clip.hook.isEmpty ? plan.title : clip.hook)   Look: \(ShortStyle.make(seed: clip.styleSeed, clip: clip).summary)") }
                func clock(_ x: Double) -> String { String(format: "%d:%04.1f", Int(x) / 60, x - Double(Int(x) / 60 * 60)) }
                print(String(format: "Short: %@ → %@  (%.1f s)", clock(clip.start), clock(clip.end), clip.duration))
                if let r = Pipeline.lineRange(plan: plan, clip: clip) { print("Lyrics: lines \(r.lowerBound + 1)–\(r.upperBound + 1): “\(plan.lines[r.lowerBound].text)” … “\(plan.lines[r.upperBound].text)”") }
                plan.shorts.removeAll { $0.name == clip.name }; plan.shorts.append(clip); try Pipeline.savePlan(plan, w)
                if noRender { continue }
                for v in 0..<max(1, variants) {
                    var cv = clip
                    if v > 0 { cv.styleSeed = clip.styleSeed &+ UInt64(v) &* 7919; print("Variant \(v + 1): \(ShortStyle.make(seed: cv.styleSeed, clip: cv).summary)") }
                    let t0 = Date()
                    let out = try await Pipeline.renderShort(plan: plan, work: w, clip: cv, suffix: variants > 1 ? " (\(["A", "B", "C", "D", "E"][min(v, 4)]))" : "", progress: progressPrinter)
                    print(String(format: "✅ %@  (%.0fs to render)", out.path, Date().timeIntervalSince(t0)))
                }
            }
        }
    }

    struct Preview: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Write still frames (PNG) at given video times to check the look.")
        @Argument var work: String
        @Option(help: "Comma-separated seconds, e.g. 1,3,20.5") var at: String
        @Option var height = 1080
        @Option(help: "Render frames of this Short (1 = the first) instead of the full video; times are inside the Short") var short: Int?
        @Option(help: "With --short: the look's word style (pill, pop, stack, sweep) to test") var words: String?
        func run() async throws {
            let w = URL(fileURLWithPath: (work as NSString).expandingTildeInPath)
            var plan = try Pipeline.loadPlan(w)
            if plan.shorts.isEmpty { plan.shorts = Pipeline.autoShorts(plan: plan) }
            var clip = short.flatMap { plan.shorts.indices.contains($0 - 1) ? plan.shorts[$0 - 1] : nil }
            if var c = clip, let m = words { c.dynamic = m != "simple"; c.textStyle = m; clip = c }
            let c = FrameComposer(plan: plan, work: w, settings: clip == nil ? VideoSettings(height: height) : VideoSettings.short(), short: clip)
            for s in at.split(separator: ",").compactMap({ Double($0) }) {
                let url = w.appendingPathComponent(String(format: "preview_%07.2f.png", s))
                let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
                CGImageDestinationAddImage(d, c.still(at: s), nil); CGImageDestinationFinalize(d)
                print(url.path)
            }
        }
    }

    struct Loop: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Looping long music video: make the long video for a looping project folder (song + loop clip), or a new one from a song and a clip.")
        @Argument(help: "A looping project folder (with loop.json), or a new folder to create") var folder: String
        @Option(help: "Song file(s) for a new project (repeat --song for a playlist)") var song: [String] = []
        @Option(help: "Title cards: none, beginning or every") var cards: String?
        @Option(help: "Joins: seamless, automatic, crossfade or albumGaps") var transition: String?
        @Option(help: "Loop clip (mp4/mov) to use") var clip: String?
        @Option(help: "Title on the title screen") var title: String?
        @Option(help: "Length in hours (0.05 = 3 minutes, for a test)") var hours = 1.0
        @Option(help: "Where to save the video") var out: String?
        @Flag(help: "Only make the loop preview (one loop, no sound)") var previewOnly = false
        @Option(help: "Print what should move in this picture (and the clip instruction it gives), then stop") var describe: String?
        @Flag(help: "Only make the YouTube thumbnail and description (beside where the video is saved)") var youtube = false
        @Flag(help: "Each song once: the video is as long as the album") var once = false
        @Flag(help: "Print the plan of the music (each join) and stop") var plan = false
        @Option(help: "Make a short preview with sound starting here (seconds into the long video), then stop") var sampleFrom: Double?
        @Option(help: "Check a clip for mirror flips and cuts, then stop") var check: String?
        @Option(help: "Find the best loop in a clip, then stop") var bestLoop: String?
        @Option(help: "Use this picture (copied in)") var picture: String?
        @Option(help: "The scene, in words") var scene: String?
        @Option(help: "Subject photo (copied in): every picture drawn shows this subject") var subject: String?
        @Option(help: "Search for a subject photo with these words and use the first result") var findSubject: String?
        @Flag(help: "Draw the picture now (costs a few cents), then stop") var draw = false
        @Flag(help: "Draw the next scene from the picture in use (same place, one major change, slightly different angle), then stop") var nextScene = false
        @Option(help: "Weather for the pictures: any, clear, softClouds, overcast, rain, storm, snow, mist, clearingStorm") var weather: String?
        @Option(help: "Time of day for the pictures: any, dawn, morning, midday, goldenEvening, dusk, night") var timeOfDay: String?
        @Option(help: "What next scenes keep: place, building or subject") var keep: String?
        @Option(help: "The look (art style)") var style: String?
        @Flag(help: "Print 10 scene ideas (from the picture when there is one), then stop") var suggest = false
        @Option(help: "Change the scene: never, time, songs or both (uses every clip in the project)") var sceneChange: String?
        @Option(help: "Minutes between scene changes by time") var sceneMinutes: Double?
        @Flag(help: "Make one YouTube Short per song (beside the long video), then stop") var shorts = false
        func run() async throws {
            if let c = bestLoop {
                let u = URL(fileURLWithPath: (c as NSString).expandingTildeInPath)
                if let r = LoopVideo.bestLoop(u) {
                    print(String(format: "best loop %.2f–%@ s  score %.2f (%@)", r.trim.start, r.trim.end.map { String(format: "%.2f", $0) } ?? "end", r.score, LoopVideo.loopQuality(r.score)))
                    if let b = LoopVideo.loopBlend(u, trim: r.trim) {
                        print(String(format: "slow dissolve: %.0f%% of the picture over %.1f s (%.1f before, %.1f after)   colour drift R %.3f G %.3f B %.3f", b.share * 100, b.slowSeconds, b.before, b.after, b.drift.x, b.drift.y, b.drift.z))
                    }
                }
                if let r = LoopVideo.bestLoop(u, minLoop: 13.4) { print(String(format: "end-to-start (the old way) score %.2f", r.score)) }
                return
            }
            if let c = check {
                let r = LoopVideo.checkClip(URL(fileURLWithPath: (c as NSString).expandingTildeInPath))
                print("length \(r.length)  mirror flips at \(r.mirrors)  cuts at \(r.cuts)  turning reverses at \(r.turns)  best part: \(r.best.map { "\($0.start)–\($0.end ?? r.length)" } ?? "the whole clip")"); return
            }
            if let d = describe {
                guard let r = await LoopVideo.describeMotion(file: URL(fileURLWithPath: (d as NSString).expandingTildeInPath)) else { throw MVError("No description came back.") }
                print("What moves: \(r.text)\nCost: \(r.cost)\n\nClip instruction:\n\(LoopVideo.clipPrompt(scene: "", motion: r.text))"); return
            }
            let dir = URL(fileURLWithPath: (folder as NSString).expandingTildeInPath)
            let fm = FileManager.default
            var p: LoopProject
            if LoopVideo.isLoopProject(dir) { p = try LoopVideo.load(dir) } else {
                guard let s = song.first else { throw MVError("Give --song for a new project.") }
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                p = LoopProject(); p.title = title ?? URL(fileURLWithPath: s).deletingPathExtension().lastPathComponent
                try await LoopVideo.addTracks(&p, dir: dir, files: song.map { URL(fileURLWithPath: $0) })
            }
            if let c = clip { let name = "clip-cli." + URL(fileURLWithPath: c).pathExtension; try? fm.removeItem(at: dir.appendingPathComponent(name)); try fm.copyItem(at: URL(fileURLWithPath: c), to: dir.appendingPathComponent(name)); p.clip = name }
            if let t = title { p.screenTitle = t }
            if let c = cards { p.cards = c == "every" ? .everySong : (c == "beginning" ? .beginning : .none) }
            if let t = transition { p.transition = LoopTransition(rawValue: t) }
            if once { p.playOnce = true }
            p.hours = hours
            if let pic = picture { let n = "picture-cli." + URL(fileURLWithPath: pic).pathExtension; try? fm.removeItem(at: dir.appendingPathComponent(n)); try fm.copyItem(at: URL(fileURLWithPath: pic), to: dir.appendingPathComponent(n)); p.picture = n }
            if let sc = scene { p.scene = sc }
            if let w = weather { p.weather = LoopWeather(rawValue: w) ?? .any }
            if let t = timeOfDay { p.timeOfDay = LoopTimeOfDay(rawValue: t) ?? .any }
            if let k = keep { p.nextFocus = NextFocus(rawValue: k) }
            if let st = style { p.style = st }
            if let c = sceneChange { p.sceneChange = LoopSceneChange(rawValue: c) ?? .never; p.sceneClips = p.clips }
            if let m = sceneMinutes { p.sceneMinutes = m }
            if let q = findSubject {
                guard let h = await SubjectPicture.search(q).first else { throw MVError("No subject found for \(q).") }
                let f = try await SubjectPicture.download(h, to: dir); p.subject = f.lastPathComponent; print("subject: \(h.title) (\(h.source)) -> \(f.lastPathComponent)")
            }
            if let sj = subject { let n = "subject-cli." + URL(fileURLWithPath: sj).pathExtension; try? fm.removeItem(at: dir.appendingPathComponent(n)); try fm.copyItem(at: URL(fileURLWithPath: sj), to: dir.appendingPathComponent(n)); p.subject = n }
            if draw { let c = try await LoopVideo.makePicture(&p, dir: dir); print("✅ \(p.picture ?? "")  cost \(OpenRouter.formatUSD(c))"); return }
            if suggest {
                let ideas: [String]
                if let pic = p.source ?? p.picture ?? p.subject { ideas = try await LoopVideo.suggestScenes(picture: dir.appendingPathComponent(pic), focus: LoopVideo.nextFocus(p, dir: dir), about: p.about) }
                else { ideas = try await LoopVideo.suggestScenes(title: p.title, style: p.style, about: p.about) }
                LoopVideo.save(p, dir); print(ideas.joined(separator: "\n")); return
            }
            if nextScene { let c = try await LoopVideo.makeNextPicture(&p, dir: dir); print("scene: \(p.scene)\nchange: \(p.sceneChanges.last ?? "")\n✅ \(p.picture ?? "")  cost \(OpenRouter.formatUSD(c))"); return }
            LoopVideo.save(p, dir)
            if youtube {
                let o = out.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) } ?? dir.appendingPathComponent("\(p.title).mp4")
                try await LoopVideo.makeYouTubeFiles(&p, dir: dir, video: o)
                print("✅ \(p.thumbnail ?? "")\n✅ \(p.listing ?? "")"); return
            }
            if plan {
                try LoopVideo.ensureAnalysis(&p, dir: dir)
                guard let pl = LoopVideo.plan(p) else { throw MVError("No plan.") }
                for (x, y) in zip(pl.plays, pl.plays.dropFirst()) {
                    let ax = p.analysis[p.tracks[x.track].file]!, ay = p.analysis[p.tracks[y.track].file]!
                    let join = y.start - x.end
                    print(String(format: "%@ → %@: %@ %.1f s  (quiet tail %.2f s, next quiet intro %.2f s; music gap %.1f s)", p.tracks[x.track].title, p.tracks[y.track].title,
                                 join < 0 ? "overlap" : "pause", abs(join), ax.quietTail, ay.quietIntro, (y.start + ay.quietIntro) - (x.end - ax.quietTail)))
                }
                print(String(format: "total %.1f s", pl.total)); return
            }
            guard let cl = p.clip else { throw MVError("No loop clip yet: give --clip.") }
            if shorts {
                let folder = (out.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).deletingLastPathComponent() } ?? dir).appendingPathComponent("\(p.title) – Shorts")
                let t0 = Date()
                let made = try await LoopVideo.makeShorts(p, dir: dir, folder: folder) { ph, _ in print(ph) }
                print(String(format: "✅ %d Shorts in %@ (%.0fs)", made.count, folder.path, Date().timeIntervalSince(t0))); return
            }
            if let f = sampleFrom {
                let o = dir.appendingPathComponent("sample.mp4"), t0 = Date()
                try await LoopVideo.renderPreview(p, dir: dir, output: o, from: f, seconds: 40)
                print(String(format: "✅ %@ (%.1fs)", o.path, Date().timeIntervalSince(t0))); return
            }
            LoopVideo.checkIfNeeded(&p, dir: dir)
            if previewOnly {
                let o = dir.appendingPathComponent("loop-preview.mp4")
                try await LoopVideo.makePreview(clip: dir.appendingPathComponent(cl), output: o, trim: p.trim); print("✅ \(o.path)"); return
            }
            let o = out.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) } ?? dir.appendingPathComponent("\(p.title).mp4")
            let t0 = Date()
            try await LoopVideo.render(p, dir: dir, output: o) { ph, f in print(String(format: "\r%3d%%  %@", Int(f * 100), ph), terminator: ""); fflush(stdout) }
            print(String(format: "\n✅ %@  (%.0fs)", o.path, Date().timeIntervalSince(t0)))
        }
    }

    struct Draw: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Draw one picture of a music video project with the picture maker (a few cents).")
        @Argument var work: String
        @Option(help: "Which picture: 1, 2, … (0 = the title card)") var picture: Int
        @Option(help: "Use this subject photo from now on (copied in)") var subject: String?
        @Option(help: "Source image every picture starts from (a file in the project, e.g. full/section_3_….png)") var source: String?
        @Option(help: "What a picture keeps: place, building or subject") var keep: String?
        @Option(help: "Weather: any, clear, softClouds, overcast, rain, storm, snow, mist, clearingStorm") var weather: String?
        @Option(help: "Time of day: any, dawn, morning, midday, goldenEvening, dusk, night") var timeOfDay: String?
        func run() async throws {
            let w = URL(fileURLWithPath: (work as NSString).expandingTildeInPath)
            var plan = try Pipeline.loadPlan(w)
            if let sj = subject { let n = "subject-cli." + URL(fileURLWithPath: sj).pathExtension; try? FileManager.default.removeItem(at: w.appendingPathComponent(n)); try FileManager.default.copyItem(at: URL(fileURLWithPath: sj), to: w.appendingPathComponent(n)); plan.subjectPicture = n }
            if let sr = source { plan.source = sr }
            if let k = keep { plan.nextFocus = NextFocus(rawValue: k) }
            if let x = weather { plan.weather = LoopWeather(rawValue: x) ?? .any }
            if let x = timeOfDay { plan.timeOfDay = LoopTimeOfDay(rawValue: x) ?? .any }
            let gen = try await Pipeline.generateSectionImage(section: picture - 1, plan: &plan, work: w)
            try Pipeline.savePlan(plan, w)
            let c = picture == 0 ? plan.intro.selectedCandidate : plan.sections[picture - 1].selectedCandidate
            print("✅ \(c?.fullFile ?? "?")  cost \(OpenRouter.formatUSD(gen.costUSD))" + (c?.subjectDistance.map { String(format: "  different from the subject photo: %.2f%@", $0, c!.looksLikeSubject ? " (TOO CLOSE: warning shown)" : "") } ?? ""))
        }
    }

    struct Fit: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Make a photo widescreen (16:9): extend it with the picture maker (the photo itself is kept; a few cents) or crop it.")
        @Argument var picture: String
        @Option(help: "Where to save it") var out: String
        @Flag(help: "Crop the middle instead of extending") var crop = false
        @Option(help: "The scene, in words (helps the new sides match)") var scene = ""
        func run() async throws {
            let u = URL(fileURLWithPath: (picture as NSString).expandingTildeInPath), o = URL(fileURLWithPath: (out as NSString).expandingTildeInPath)
            print(PictureFit.describe(u) + (PictureFit.needsFitting(u) ? "" : " (close enough to widescreen: no change needed)"))
            if crop { try PictureFit.crop(u, rect: PictureFit.cropRect(aspect: PictureFit.aspect(u) ?? PictureFit.target), output: o); print("✅ \(o.path)"); return }
            let cost = try await PictureFit.extend(u, output: o, scene: scene)
            print("✅ \(o.path)  cost \(OpenRouter.formatUSD(cost))")
        }
    }

    struct YouTube: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "youtube", abstract: "Make the YouTube thumbnail and the search-friendly description for a lyric video project (beside the video).")
        @Argument var work: String
        func run() async throws {
            let w = URL(fileURLWithPath: (work as NSString).expandingTildeInPath)
            let plan = try Pipeline.loadPlan(w)
            guard let f = plan.intro.selectedCandidate?.fullFile ?? plan.sections.compactMap({ $0.selectedCandidate?.fullFile }).first else { throw MVError("No picture yet.") }
            let video = Pipeline.videoURL(plan: plan, work: w, config: Config.load())
            let listing = await YouTubeKit.lyricListing(plan)
            let r = try YouTubeKit.writeFiles(beside: video, picture: w.appendingPathComponent(f), thumbTitle: plan.title, badge: "Lyric video", line: plan.subject.isEmpty ? nil : plan.subject, listing: listing)
            print("✅ \(r.thumbnail.path)\n✅ \(r.description.path)")
        }
    }

    struct Models: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Check the oMLX connection and list the models in use.")
        func run() async throws {
            let o = OMLX(config: Config.load())
            try await o.ensureReady()          // starts oMLX's engine hidden if nothing is serving
            let ids = try await o.models()
            print("oMLX at \(o.baseURL.absoluteString)\(OMLXServer.shared.ownsServer ? " (started by this app, no window)" : " (already running)") — \(ids.count) models")
            print("  speech  : \(o.stt)\(ids.contains(o.stt) ? "" : "   ⚠️ not found")")
            print("  language: \(o.llm)\(ids.contains(o.llm) ? "" : "   ⚠️ not found")")
            print("  all: " + ids.joined(separator: ", "))
        }
    }

    struct Settings: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "settings", abstract: "Change oMLX or OpenRouter settings.")
        @Option var omlxKey: String?
        @Option var omlxUrl: String?
        @Option var sttModel: String?
        @Option var llmModel: String?
        @Option(help: "OpenRouter API key for openai/gpt-image-2.5-sunburst image generation") var openrouterKey: String?
        @Flag(help: "Check remaining OpenRouter credits") var credits = false
        @Option(help: "Folder where project folders are created") var projectsFolder: String?
        @Option(help: "Folder where finished videos and Shorts are saved") var outputFolder: String?
        func run() async throws {
            var c = Config.load()
            if let f = projectsFolder { c.projectsFolder = f }; if let f = outputFolder { c.outputFolder = f }
            if let a = omlxKey { c.omlxKey = a }; if let u = omlxUrl { c.omlxURL = u }; if let m = sttModel { c.sttModel = m }; if let m = llmModel { c.llmModel = m }
            if let ok = openrouterKey { c.openRouterKey = ok }
            try c.save(); print("Saved to \(Config.url.path)")
            if credits {
                let info = try await OpenRouter.fetchCredits(apiKey: c.effectiveOpenRouterKey)
                print("OpenRouter credits remaining: \(OpenRouter.formatCredits(info.remaining)) (total purchased: \(OpenRouter.formatCredits(info.totalCredits)), used: \(OpenRouter.formatCredits(info.totalUsage)))")
            }
        }
    }
}
