// Shows the two on-device models (Parakeet Ultra and the language model): installed or not, size, and live download progress.
import SwiftUI

struct ModelRows: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            row(icon: "waveform", name: "Parakeet Ultra", role: "Listens to your song and finds exactly when each word is sung",
                ready: model.speechReady, size: model.speechSizeText, progress: model.speechProgress,
                download: { model.downloadSpeechModel() }, again: { model.downloadSpeechModel(force: true) })
            row(icon: "text.bubble", name: model.llmReady ? model.llmName : "Language model", role: "Reads your lyrics and writes the picture ideas",
                ready: model.llmReady, size: model.llmSizeText, progress: model.llmProgress,
                download: { model.downloadLanguageModel() }, again: { model.downloadLanguageModel(force: true) })
            if let n = model.modelNote { Text(n).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
        }
    }

    func row(icon: String, name: String, role: String, ready: Bool, size: String, progress: Double?, download: @escaping () -> Void, again: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title2).frame(width: 30).foregroundStyle(ready ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.headline)
                Text(role).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let p = progress {
                    HStack(spacing: 8) {
                        ProgressView(value: p).frame(maxWidth: 260)
                        Text("Downloading… \(Int(p * 100))%").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    }
                } else if ready {
                    Label("Downloaded · \(size)", systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(.green)
                } else {
                    Label("Not downloaded yet", systemImage: "exclamationmark.circle.fill").font(.callout).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 8)
            if progress == nil {
                if ready {
                    Button("Download again", action: again).disabled(model.downloadingModel || model.settingUp)
                        .help("Deletes this model and downloads a fresh, checked copy. Use it if planning stops with an error about this model.")
                } else {
                    Button("Download", action: download).buttonStyle(.borderedProminent).disabled(model.downloadingModel || model.settingUp)
                        .help("Downloads this model once. After that everything works without internet.")
                }
            }
        }
    }
}
