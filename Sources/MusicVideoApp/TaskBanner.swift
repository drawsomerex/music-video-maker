// The strip across the top of the window: every task that takes a while shows here with a progress bar, the time it has taken and a Cancel button.
// Parallel tasks get a row each. When a task finishes, a green "Done" row (with what it cost) stays for a few seconds and fades.
import SwiftUI
import MVCore

struct DoneNote: Equatable { var id = UUID(); var text: String; var watch = false; var reveal: URL? = nil }      // watch / reveal: a finished video, with a button (stays until closed)      // watch: the finished video, with a button to open it (stays until closed)

struct BannerRow: View {
    let title: String
    var detail: String? = nil
    let fraction: Double?              // nil = no bar value known (spinner only)
    let estimated: Bool
    let started: Date
    var cancelHelp = "Stops this task. Nothing you made so far is lost."
    let cancel: (() -> Void)?
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let el = max(0, ctx.date.timeIntervalSince(started))
            let f = fraction.map { min(max($0, 0), 1) }
            HStack(spacing: 14) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(title).font(.callout.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                        if let d = detail { Text(d).font(.callout).foregroundStyle(.secondary).lineLimit(1) }
                        Spacer()
                        Text((f.map { "\(estimated ? "about " : "")\(Int($0 * 100))% · " } ?? "") + String(format: "%d:%02d", Int(el) / 60, Int(el) % 60))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    if let f { ProgressView(value: max(0.03, f)).progressViewStyle(.linear) } else { ProgressView().progressViewStyle(.linear) }
                }
                .frame(maxWidth: 560)
                Spacer(minLength: 0)
                if let cancel { Button("Cancel", action: cancel).buttonStyle(.bordered).controlSize(.small).help(cancelHelp) }
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
        }
    }
}

struct TaskBanners: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            if model.busy {
                BannerRow(title: model.busyPhase.isEmpty ? "Working in background…" : model.busyPhase, fraction: model.busyProgress, estimated: false, started: model.busyStarted, cancel: { model.cancelBackgroundTask() })
                Divider()
            }
            if let j = model.clipJob, j.failed == nil {
                if j.waiting {
                    HStack(spacing: 12) {
                        Image(systemName: "film.fill").foregroundStyle(.tint)
                        Text(j.chain ? "Clip \(j.index + 1) of \(j.secondsList.count) is ready — watch it under the picture and choose what to do." : "Your clip is ready — watch it under the picture.").font(.callout.weight(.semibold))
                        Spacer()
                    }.padding(.horizontal, 20).padding(.vertical, 8)
                } else {
                    BannerRow(title: j.bulk.map { "Making video clips — picture \($0.n) of \($0.of)" } ?? ("Making a video clip" + (j.chain ? " — clip \(j.index + 1) of \(j.secondsList.count)" : "")), detail: j.phase, fraction: j.estimatedFraction(now: Date()), estimated: true, started: j.started,
                              cancelHelp: "Stops. A clip that is already being made is still charged by HeyGen; finished clips are kept.", cancel: { model.cancelClipJob() })
                }
                Divider()
            }
            if let v = model.videoJob {
                BannerRow(title: "Making your video", detail: v.phase, fraction: v.progress, estimated: false, started: v.started,
                          cancelHelp: "Stops making the video. Nothing else is lost.", cancel: { model.cancelVideo() })
                Text("You can keep working. Changes you make now go into the next video you make.").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 48).padding(.bottom, 6)
                Divider()
            }
            if let j = model.loopJob {
                BannerRow(title: j.title.replacingOccurrences(of: "…", with: ""), detail: j.phase.isEmpty ? nil : j.phase, fraction: j.fraction(now: Date()), estimated: j.progress == nil, started: j.started,
                          cancelHelp: "Stops this step. A clip that HeyGen is already making is still charged; it is collected the next time you open this looping video.", cancel: { model.cancelLoopJob() })
                Divider()
            }
            if let sp = model.shortProgress {
                BannerRow(title: model.shortPhase.isEmpty ? "Making Shorts…" : model.shortPhase, fraction: sp, estimated: false, started: model.shortStarted, cancel: { model.cancelShortRender() })
                Divider()
            }
            if let d = model.doneNote {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(d.text).font(.callout.weight(.semibold))
                    if let u = d.reveal {
                        Button { model.doneNote = nil; NSWorkspace.shared.activateFileViewerSelecting([u]) } label: { Label("Show in Finder", systemImage: "folder") }.buttonStyle(.borderedProminent).controlSize(.small)
                    }
                    if d.watch {
                        Button { model.doneNote = nil; model.stage = .done } label: { Label("Watch it", systemImage: "play.fill") }.buttonStyle(.borderedProminent).controlSize(.small)
                            .help("Opens the finished video, with buttons to show it in Finder and to share it.")
                    }
                    Spacer()
                    Button { model.doneNote = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20).padding(.vertical, 8).background(Color.green.opacity(0.10)).transition(.opacity)
                .task(id: d.id) { if d.watch || d.reveal != nil { return }; try? await Task.sleep(nanoseconds: 7_000_000_000); if model.doneNote?.id == d.id { withAnimation { model.doneNote = nil } } }
                Divider()
            }
        }
        .background(.regularMaterial)
        .animation(.smooth(duration: 0.25), value: model.busy)
        .animation(.smooth(duration: 0.25), value: model.clipJob?.waiting)
        .animation(.smooth(duration: 0.25), value: model.shortProgress == nil)
        .animation(.smooth(duration: 0.25), value: model.videoJob == nil)
        .animation(.smooth(duration: 0.25), value: model.loopJob == nil)
        .animation(.smooth(duration: 0.25), value: model.doneNote)
    }
}
