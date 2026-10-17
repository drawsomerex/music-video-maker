// The Help window: ask a question in your own words (answered from the guide and what is on screen), or read the whole guide.
import SwiftUI
import MVCore

/// "Help" button used on every screen. It remembers which screen it was pressed on so the helper knows the situation.
struct HelpButton: View {
    @EnvironmentObject var model: AppModel
    let screen: String
    var body: some View {
        Button { model.helpScreen = screen; model.showHelp = true } label: { Label("Help", systemImage: "questionmark.circle") }
            .buttonStyle(.bordered)
            .help("Ask a question in your own words, or read the guide. The helper knows what is on your screen right now.")
    }
}

struct HelpCenterView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0                       // 0 = ask, 1 = read the guide
    @State private var question = ""
    @State private var answer: HelpAnswer?
    @State private var asking = false
    @State private var asked = ""
    @State private var openSection: String = HelpGuide.sections[0].id
    @State private var search = ""
    @FocusState private var focused: Bool

    var suggestions: [String] {
        let s = model.helpScreen.lowercased()
        if s.contains("shorts") { return ["How do I make Shorts?", "How long can a Short be?", "Where are my Shorts saved?"] }
        if s.contains("pictures") { return ["How do I add my own picture?", "What will the blank pictures cost?", "Why do the words look early?", "How do I choose where the camera moves?"] }
        if s.contains("video") && !s.contains("making") { return ["Where is my video saved?", "How do I make Shorts?", "How do I change a picture and make it again?"] }
        if s.contains("making") || s.contains("planning") { return ["How long will this take?", "Can I cancel?"] }
        return ["How do I get started?", "What does “Plan my video” do?", "Why is “Plan my video” grey?", "How do I cut the lyrics into pictures?"]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "questionmark.circle.fill").font(.system(size: 28)).foregroundStyle(.tint)
                Text("Help").font(.title.bold())
                Spacer()
                Picker("", selection: $tab) { Text("Ask a question").tag(0); Text("Read the guide").tag(1) }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 270)
                    .help("“Ask a question” answers in plain words. “Read the guide” shows everything the app can do.")
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction).help("Close the help window.")
            }
            if tab == 0 { ask } else { guide }
        }
        .padding(22).frame(minWidth: 620, idealWidth: 720, minHeight: 440, idealHeight: 620)
        .onAppear { focused = true }
    }

    // MARK: ask
    var ask: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ask anything about the app. The helper answers using the guide and what is on your screen right now. If the guide doesn't cover it, or the app can't do it, it will say so instead of guessing.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                TextField("Type your question here, for example: how do I add my own pictures?", text: $question, axis: .vertical)
                    .textFieldStyle(.roundedBorder).controlSize(.large).lineLimit(1...3).focused($focused)
                    .onSubmit { send(question) }
                    .help("Write your question the way you would say it. Press Return to ask.")
                Button { send(question) } label: { Label("Ask", systemImage: "paperplane.fill") }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(asking || question.trimmingCharacters(in: .whitespaces).isEmpty)
                    .help("Sends your question to the helper on this Mac. Nothing leaves your computer.")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Or press a common question:").font(.callout.weight(.medium))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(suggestions, id: \.self) { s in
                        Button { question = s; send(s) } label: { Text(s).frame(maxWidth: .infinity, alignment: .leading) }
                            .buttonStyle(.bordered).disabled(asking).help("Ask this question. The answer comes from the guide, on your Mac.")
                    }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if asking {
                        HStack(spacing: 10) { ProgressView(); Text("Looking it up in the guide…").foregroundStyle(.secondary) }
                    } else if let a = answer {
                        Text(asked).font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                        Text(a.text).font(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        ForEach(a.notes, id: \.self) { n in Label(n, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
                        if !a.sources.isEmpty {
                            Text("Based on the guide: " + a.sources.joined(separator: " · ")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        HStack {
                            if let s = HelpGuide.relevant(to: asked, top: 1).first {
                                Button { openSection = s.id; tab = 1 } label: { Label("Open “\(s.title)” in the guide", systemImage: "book") }
                                    .help("Read the full text this answer is based on.")
                            }
                            Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(a.text, forType: .string) } label: { Label("Copy answer", systemImage: "doc.on.doc") }
                        }
                        Text("This answer comes from a small AI on your Mac. Check important details in the guide.").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(.background.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
            HStack {
                Button { dismiss(); model.showGuide = true } label: { Label("Quick start (5 steps)", systemImage: "list.number") }
                    .help("The short step-by-step introduction.")
                Button { dismiss(); model.showReport = true } label: { Label("Report a problem", systemImage: "ladybug") }
                    .help("Tell the author about something that is not working. You can see here later whether it is fixed.")
                Spacer()
            }
        }
    }

    func send(_ q: String) {
        let text = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !asking else { return }
        asking = true; asked = text; answer = nil
        let status = model.helpStatus(screen: model.helpScreen), cfg = model.config
        Task {
            let a = await HelpAssistant.answer(question: text, status: status, config: cfg)
            await MainActor.run { answer = a; asking = false }
        }
    }

    // MARK: guide
    var guide: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Search the guide", text: $search).textFieldStyle(.roundedBorder)
                    .help("Type a word, such as “camera” or “cost”, to find the right section.")
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(filtered) { s in
                            Button { openSection = s.id } label: {
                                Text(s.title).font(.callout.weight(openSection == s.id ? .semibold : .regular)).multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5).padding(.horizontal, 8)
                                    .background(RoundedRectangle(cornerRadius: 7).fill(openSection == s.id ? Color.accentColor.opacity(0.18) : .clear))
                            }.buttonStyle(.plain).help("Read this part of the guide.")
                        }
                    }
                }
            }.frame(width: 215)
            ScrollView {
                if let s = HelpGuide.section(openSection) ?? filtered.first {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(s.title).font(.title2.bold())
                        Text(s.body.split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n"))
                            .font(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                }
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(.background.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
        }
    }

    var filtered: [HelpSection] {
        let q = search.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return HelpGuide.sections }
        let hits = HelpGuide.relevant(to: q, top: 8)
        return hits.isEmpty ? HelpGuide.sections.filter { ($0.title + $0.body).localizedCaseInsensitiveContains(q) } : hits
    }
}
