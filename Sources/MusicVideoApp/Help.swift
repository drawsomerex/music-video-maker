// Plain-language help: the step bar, the Quick Guide, and the "what to do next" card that guide a first-time user.
import SwiftUI

/// The three steps of making a video. Shown at the top of every main screen so you always know where you are.
struct StepBar: View {
    let current: Int          // 1 = song, 2 = pictures, 3 = video
    private let steps = [("1", "Song", "music.note"), ("2", "Pictures", "photo.on.rectangle"), ("3", "Video", "film")]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                let n = i + 1
                HStack(spacing: 7) {
                    ZStack {
                        Circle().fill(n < current ? Color.green : (n == current ? Color.accentColor : Color.secondary.opacity(0.25))).frame(width: 24, height: 24)
                        if n < current { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white) }
                        else { Text(s.0).font(.caption.weight(.bold)).foregroundStyle(n == current ? .white : .secondary) }
                    }
                    Text(s.1).font(.callout.weight(n == current ? .semibold : .regular)).foregroundStyle(n == current ? .primary : .secondary).lineLimit(1).fixedSize()
                }
                if i < steps.count - 1 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
            }
        }
        .help("Making a video takes three steps: 1) choose your song and lyrics, 2) add a picture for each part of the song, 3) press the button to make the video.")
    }
}

/// A large, friendly card that says what to do next and offers the one button that does it.
struct NextStepCard: View {
    let icon: String
    let title: String
    let detail: String
    var tint: Color = .accentColor
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 26)).foregroundStyle(tint).frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(tint.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(tint.opacity(0.35)))
    }
}

/// Step-by-step instructions in large type. Opens on first launch and from Help ▸ Quick Guide (or the ? button).
struct QuickGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("seenQuickGuide") private var seen = false
    private let items: [(String, String, String)] = [
        ("music.note", "Choose your song", "Drag your MP3 onto the box (or click it). Type the song's title and paste the lyrics on the right. The words you paste are exactly what appears on the screen."),
        ("sparkles", "Press “Plan my video”", "The app listens to your song and matches each lyric to the moment it is sung. It then splits the song into parts and suggests a picture for each one. This takes a minute or two."),
        ("photo.on.rectangle", "Add a picture for each part", "Click a part in the list on the left. Then either press “Make this picture” (needs an OpenRouter key, see Settings) or drag a picture you made yourself into the box. “Make all missing pictures” does every part at once."),
        ("play.rectangle", "Watch a preview", "Press “Preview” to watch the video before it is made. If the words are a little early or late, use the “Show sooner” and “Show later” buttons under the preview."),
        ("film", "Press “Make my video”", "Your finished video is saved in your Music Videos folder. The last screen has buttons to show it in Finder and to share it. Short vertical clips for YouTube Shorts can be made too."),
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Image(systemName: "questionmark.circle.fill").font(.system(size: 30)).foregroundStyle(.tint); Text("How to make a music video").font(.title.bold()) }
            ForEach(Array(items.enumerated()), id: \.offset) { i, it in
                HStack(alignment: .top, spacing: 14) {
                    ZStack { Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 38, height: 38); Text("\(i + 1)").font(.headline).foregroundStyle(.tint) }
                    VStack(alignment: .leading, spacing: 3) {
                        Label(it.1, systemImage: it.0).font(.headline)
                        Text(it.2).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Divider()
            Text("Tip: rest your mouse on any button for a moment and a short explanation appears. Your work is saved automatically, so you can close the app and come back to it with “Open earlier project”.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack { Spacer(); Button("Got it") { seen = true; dismiss() }.buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction) }
        }
        .padding(28).frame(width: 600)
    }
    static var shouldShowFirst: Bool { !UserDefaults.standard.bool(forKey: "seenQuickGuide") }
}
