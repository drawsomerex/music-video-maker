// The "Ask a question" helper: the local AI answers ONLY from the help guide and the facts about the current screen, and says so when it does not know.
import Foundation
import SwiftUI
import MVCore

struct HelpAnswer {
    var text: String
    var sources: [String]            // titles of the guide sections the answer was based on
    var fromAI: Bool                 // false = the AI was not used (not ready, or nothing in the guide matched)
    var notes: [String] = []         // warnings about wording the guide does not contain
}

enum HelpAssistant {
    static let dontKnow = "I don't know. That isn't covered in the help guide, so I can't answer it reliably. You can open “Read the guide” to look yourself."

    static func answer(question: String, status: String, config: Config) async -> HelpAnswer {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return HelpAnswer(text: "Type a question first.", sources: [], fromAI: false) }
        var found = HelpGuide.relevant(to: q, top: 4)
        // A question about what is possible always gets the list of limits, so "can it …?" can be answered with a clear no.
        if let limits = HelpGuide.section("limits"), !found.contains(where: { $0.id == "limits" }),
           q.lowercased().contains("can") || q.lowercased().contains("possible") || q.lowercased().contains("able") || q.lowercased().contains("support") { found.append(limits) }
        guard !found.isEmpty else { return HelpAnswer(text: dontKnow, sources: [], fromAI: false) }

        let guide = found.map { "### \($0.title)\n\($0.body)" }.joined(separator: "\n\n")
        let prompt = """
        You are the built-in help assistant of the Mac app “Music Video Maker”. The user may be a beginner, so use short, plain words.
        Answer ONLY with facts from the GUIDE and the SCREEN STATUS below. Rules:
        1. Never invent buttons, menus, settings or features. Use the exact names of buttons as written in the guide, in “quotes”.
        2. If the guide clearly says the app cannot do something, answer: “That isn't possible in this app.” and say what can be done instead.
        3. If the guide and status do not clearly answer the question, answer exactly: “I don't know. That isn't covered in the help guide.” and nothing else. Do not guess.
        4. For “how do I…” questions give short numbered steps. For other questions give 1 to 3 short sentences. Never more than 120 words.
        5. Use the SCREEN STATUS to give advice for this exact situation (for example why a button is grey, or what is still missing). Do not repeat the status.
        6. When the guide lists steps for the user's task, give those steps in order and do not skip any. Copy numbers (seconds, sizes, prices) exactly from the guide; if the guide gives no number, give none. If the guide describes two ways (for example the whole song versus one line), give the one that matches the question first. Never add a step the guide does not contain.

        GUIDE:
        \(guide)

        SCREEN STATUS:
        \(status)

        QUESTION: \(q)

        ANSWER:
        """
        let sources = found.map(\.title)
        do {
            let omlx = OMLX(config: config)
            try await omlx.ensureReady()
            var reply = try await omlx.chat(model: omlx.llm, parts: [.text(prompt)], maxTokens: 380).trimmingCharacters(in: .whitespacesAndNewlines)
            if reply.isEmpty { return HelpAnswer(text: dontKnow, sources: [], fromAI: true) }
            if reply.lowercased().hasPrefix("i don't know") || reply.lowercased().hasPrefix("i don’t know") { return HelpAnswer(text: dontKnow, sources: [], fromAI: true) }
            reply = reply.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
            // Any button name in “quotes” must appear in the guide or the screen status; otherwise warn instead of letting an invented name pass.
            let known = (HelpGuide.sections.map(\.body).joined(separator: " ") + " " + HelpGuide.sections.map(\.title).joined(separator: " ") + " " + status).lowercased()
            var notes: [String] = []
            for name in quoted(reply) where name.count >= 4 && name.count <= 60 {
                if !known.contains(name.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,…"))) { notes.append("I'm not sure about the name “\(name)”. Please check it in the guide.") }
            }
            return HelpAnswer(text: reply, sources: sources, fromAI: true, notes: Array(Set(notes)).sorted())
        } catch {
            // The AI is not available: show the most relevant guide text instead of nothing.
            let first = found[0]
            return HelpAnswer(text: "The helper isn't ready right now, so here is the part of the guide that matches your question:\n\n" + first.title + "\n" + first.body, sources: sources, fromAI: false)
        }
    }

    /// Text inside “curly”, "straight" quotes.
    static func quoted(_ s: String) -> [String] {
        var out: [String] = []
        for (open, close) in [("“", "”"), ("\"", "\"")] {
            var rest = Substring(s)
            while let a = rest.range(of: open), let b = rest[a.upperBound...].range(of: close) {
                out.append(String(rest[a.upperBound..<b.lowerBound])); rest = rest[b.upperBound...]
            }
        }
        return out
    }
}

extension AppModel {
    /// Plain facts about what is on screen right now, given to the helper so it can answer for this exact situation.
    func helpStatus(screen: String) -> String {
        var l: [String] = []
        l.append("Screen: \(screen)")
        l.append("App version: \(Updater.current)")
        if needsNativeSetup { l.append("The on-device models are not all downloaded yet (setup screen).") }
        else if isNativeBuild { l.append("Models: Parakeet Ultra \(speechReady ? "downloaded" : "NOT downloaded"); language model \(llmReady ? "downloaded (\(llmName))" : "NOT downloaded").") }
        if downloadingModel { l.append("A model is downloading right now.") }
        if busy { l.append("A background task is running: \(busyPhase.isEmpty ? "working" : busyPhase) (\(Int(busyProgress * 100))%).") }
        if stage == .working { l.append("The app is planning the video: \(phase) (\(Int(progress * 100))%).") }
        if let j = videoJob { l.append("The app is making the video in the strip at the top: \(j.phase) (\(Int(j.progress * 100))%).") }
        if stage == .rendering { l.append("The app is making the video: \(phase) (\(Int(progress * 100))%).") }
        if isRecording { l.append("Recording is in progress (\(Int(recordingSeconds)) seconds).") }
        if stage == .loop, let p = loopProject {
            l.append("An open looping video: \(p.title). \(p.tracks.count) tracks; picture \(p.picture == nil ? "missing" : "ready"); loop clip \(p.clip == nil ? "missing" : "ready"). Lyrics are optional.")
            l.append("Clip choice: \(p.clipLength ?? 15) seconds used, \(p.sharpClip ? "Sharp 2K" : "Standard 768p"). Target: \(p.playOnce ? "Each song once" : LoopVideo.clock(p.hours * 3600)).")
            if let schedule = loopPlan { l.append("Scheduled output: \(LoopVideo.clock(schedule.total)).") }
            if let job = loopJob { l.append("Loop task: \(job.title), \(job.phase).") }
            if p.pendingJob != nil { l.append("An accepted paid clip job is pending recovery.") }
        } else if let p = plan {
            l.append("An open video: “\(p.title)”. Song length \(Int(p.songDuration)) s; \(p.lines.count) lyric lines; \(p.sections.count) parts plus the title card.")
            l.append("Pictures ready: \(loadedCount) of \(totalImages); blank: \(missing.count).")
            l.append("Setting and theme: \(p.setting.isEmpty ? "none set" : p.setting). Picture style words: \(p.style.isEmpty ? "none" : String(p.style.prefix(80))).")
            l.append("Lyric timing: \(p.timing == "exact" ? "exact" : "rough (the top bar offers “Fix the timing”)"). Caption timing offset: \(captionShiftText).")
            l.append("Lyric parts: \(p.partStarts.isEmpty ? "divided automatically" : (p.partsFromVerses ? "cut at the user's verse breaks" : "cut by the user with dividers")).")
            l.append("Shorts in the list: \(p.shorts.count). Video file \(videoFile == nil ? "not made yet" : "already made"). Sharpness chosen: \(quality)p. Also make short clips: \(autoRenderShorts ? "yes" : "no").")
            l.append("Spent on pictures for this song: \(OpenRouter.formatUSD(p.totalGenerationCostUSD)); estimated cost to draw the blank pictures: \(OpenRouter.formatUSD(missingImagesCostUSD)).")
        } else {
            l.append("No video is open.")
        }
        if stage == .setup || (plan == nil && stage != .loop) {
            var why: [String] = []
            if audioURL == nil { why.append("no song chosen") }
            if title.trimmingCharacters(in: .whitespaces).isEmpty { why.append("no title") }
            if lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { why.append("no lyrics") }
            l.append("First screen: song \(audioURL?.lastPathComponent ?? "not chosen"); title “\(title)”; \(lyrics.isEmpty ? "no lyrics" : "\(LyricText.rows(lyrics).count) lyric lines")." + (why.isEmpty ? " “Plan my video” is available." : " “Plan my video” is grey because: \(why.joined(separator: ", ")).") + " Look of the pictures: \(selectedStyleName). Setting field: \(settingTheme.isEmpty ? "empty" : settingTheme).")
        }
        l.append("Picture maker (OpenRouter) key: \(hasOpenRouterKey ? "entered" : "NOT entered")" + (openRouterCredits.map { "; credit left \(OpenRouter.formatCredits($0))" } ?? "") + ".")
        l.append("Saving to: \(config.projectsRoot.path).")
        if let e = errorMessage { l.append("Last error shown: \(e.prefix(200))") }
        if let n = notice { l.append("Last notice: \(n.prefix(200))") }
        return l.joined(separator: "\n")
    }
}
