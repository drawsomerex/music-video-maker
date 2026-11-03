// Activity: everything that runs, in one place (drawing, clips, the director, rendering, updates). It replaces the strips and banners of the
// original design. The panel opens on the right when something starts; the top bar's "N running" tag shows or hides it.
import SwiftUI
import MVCore

struct ActivityItem: Identifiable {
    let id: String; let title: String; var detail: String? = nil; var fraction: Double?; var estimated = false; let started: Date; var cancel: (() -> Void)?; var cancelHelp = "Stops this task. Nothing you made so far is lost."
}

extension AppModel {
    /// Every running job as one list.
    var activityItems: [ActivityItem] {
        var l: [ActivityItem] = []
        if stage == .working { l.append(.init(id: "plan", title: "Planning your video", detail: phase, fraction: progress, started: busyStarted, cancel: { self.cancelMainTask() })) }
        if busy { l.append(.init(id: "busy", title: busyPhase.isEmpty ? "Working in background…" : busyPhase, fraction: busyProgress, started: busyStarted, cancel: { self.cancelBackgroundTask() })) }
        if let j = clipJob, j.failed == nil, !j.waiting {
            l.append(.init(id: "clip", title: j.bulk.map { "Making video clips — picture \($0.n) of \($0.of)" } ?? ("Making a video clip" + (j.chain ? " — clip \(j.index + 1) of \(j.secondsList.count)" : "")), detail: j.phase,
                           fraction: j.estimatedFraction(now: Date()), estimated: true, started: j.started, cancel: { self.cancelClipJob() }, cancelHelp: "Stops. A clip that is already being made is still charged; finished clips are kept."))
        }
        if let v = videoJob { l.append(.init(id: "video", title: "Making your video", detail: v.phase, fraction: v.progress, started: v.started, cancel: { self.cancelVideo() }, cancelHelp: "Stops making the video. Nothing else is lost.")) }
        if let j = loopJob { l.append(.init(id: "loop", title: j.title.replacingOccurrences(of: "…", with: ""), detail: j.phase.isEmpty ? nil : j.phase, fraction: j.fraction(now: Date()), estimated: j.progress == nil, started: j.started, cancel: { self.cancelLoopJob() })) }
        if let sp = shortProgress { l.append(.init(id: "short", title: shortPhase.isEmpty ? "Making Shorts…" : shortPhase, fraction: sp, started: shortStarted, cancel: { self.cancelShortRender() })) }
        return l
    }
    var hasActivity: Bool { !activityItems.isEmpty || directorRun != nil || doneNote != nil || (clipJob?.waiting == true) }
}

struct NewActivityPanel: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var nd: NewDesignState
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                ClassicalHeading(text: "Activity", note: "Everything that runs, in one place", size: 20)
                Spacer()
                Button { nd.activityOpen = false } label: { Image(systemName: "xmark").font(.system(size: 10)) }.buttonStyle(.plain).foregroundStyle(Classical.neutral600).help("Hide this panel")
            }.padding(14)
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let r = model.directorRun { director(r) }
                    ForEach(model.activityItems) { row($0) }
                    if let j = model.clipJob, j.waiting {
                        Text(j.chain ? "Clip \(j.index + 1) of \(j.secondsList.count) is ready. Watch it under the picture and choose what to do." : "Your clip is ready. Watch it under the picture.").font(Classical.body(12)).foregroundStyle(Classical.accent800)
                    }
                    if let d = model.doneNote { done(d) }
                    if !model.hasActivity { Text("Nothing is running.").font(Classical.body(12)).foregroundStyle(Classical.neutral600) }
                }.padding(14)
            }
        }
        .frame(width: 310).background(Classical.paper).overlay(alignment: .leading) { VHairline() }
    }

    func row(_ a: ActivityItem) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let el = max(0, ctx.date.timeIntervalSince(a.started)); let f = a.fraction.map { min(max($0, 0), 1) }
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(a.title).font(Classical.body(13, weight: .semibold)).lineLimit(2).foregroundStyle(Classical.text)
                    Spacer(minLength: 6)
                    Text((f.map { "\(a.estimated ? "about " : "")\(Int($0 * 100))% · " } ?? "") + String(format: "%d:%02d", Int(el) / 60, Int(el) % 60)).font(Classical.body(11).monospacedDigit()).foregroundStyle(Classical.neutral600)
                }
                if let d = a.detail, !d.isEmpty { Text(d).font(Classical.body(11)).foregroundStyle(Classical.neutral600).lineLimit(2) }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Classical.neutral300.opacity(0.5))
                        Rectangle().fill(Classical.accent).frame(width: g.size.width * CGFloat(max(0.03, f ?? 0.03)))
                    }
                }.frame(height: 2)
                if let c = a.cancel { HStack { Spacer(); Button("Cancel", action: c).buttonStyle(.classicalSmall).help(a.cancelHelp) } }
            }
            Hairline().padding(.top, 6).frame(maxHeight: .infinity, alignment: .bottom).hidden()
        }
    }

    func director(_ run: DirectorRun) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(run.waiting ? "The director is paused" : (run.paused ? "Pausing after this step…" : "The director is at work")).font(Classical.body(13, weight: .semibold))
            Text("Step \(min(run.current + 1, run.steps.count)) of \(run.steps.count)\(run.detail.isEmpty ? "" : " · " + run.detail)").font(Classical.body(11)).foregroundStyle(Classical.neutral600)
            ForEach(Array(run.steps.enumerated()), id: \.offset) { i, name in
                HStack(spacing: 8) {
                    Image(systemName: i < run.current ? "checkmark.circle" : (i == run.current ? (run.waiting ? "pause.circle" : "circle.dotted") : "circle")).font(.system(size: 12))
                        .foregroundStyle(i < run.current ? Classical.ok : (i == run.current ? Classical.accent : Classical.neutral500))
                    Text(name).font(Classical.body(12, weight: i == run.current ? .semibold : .regular)).foregroundStyle(i <= run.current ? Classical.text : Classical.neutral600)
                }
            }
            if run.waiting {
                Text(run.loop ? "Paused. Rewrite the scenes still to come, or change the Look. Press Continue to carry on with your changes." : "Paused. Change any picture idea or the Look. The pictures still to come use your changes when you press Continue.")
                    .font(Classical.body(11)).foregroundStyle(Classical.neutral700).fixedSize(horizontal: false, vertical: true)
                if run.loop, run.scenes.count > run.done {
                    ForEach(run.done..<run.scenes.count, id: \.self) { k in
                        CField(label: "Scene \(k + 1)", prompt: "Scene \(k + 1)", text: Binding(get: { model.directorRun?.scenes[safe: k] ?? "" }, set: { v in if model.directorRun?.scenes.indices.contains(k) == true { model.directorRun?.scenes[k] = v } }), axis: .vertical, lines: 1...3)
                    }
                }
            }
            HStack {
                if run.paused { Button("Continue") { model.continueDirector() }.buttonStyle(.classicalPrimary).help("Carries on from here, with any changes you made.") }
                else { Button("Pause") { model.pauseDirector() }.buttonStyle(.classical).help("Stops at the next safe point so you can change ideas, then Continue.") }
                Button("Stop") { model.stopDirector() }.buttonStyle(.classical).help("Stops the director. Everything made so far is kept.")
            }
            Text("Pause stops after the picture being drawn, so you can change ideas or the Look. Continue uses your changes.").font(Classical.body(11)).foregroundStyle(Classical.neutral600)
        }
        .padding(10).overlay(RoundedRectangle(cornerRadius: 4).stroke(Classical.accent300, lineWidth: 1))
    }

    func done(_ d: DoneNote) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Image(systemName: "checkmark.circle").foregroundStyle(Classical.ok)
                Text(d.text).font(Classical.body(12, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button { model.doneNote = nil } label: { Image(systemName: "xmark").font(.system(size: 9)) }.buttonStyle(.plain).foregroundStyle(Classical.neutral600)
            }
            HStack {
                if let u = d.reveal { Button("Show in Finder") { model.doneNote = nil; NSWorkspace.shared.activateFileViewerSelecting([u]) }.buttonStyle(.classicalSmall) }
                if d.watch { Button("Watch it") { model.doneNote = nil; nd.route = .export }.buttonStyle(.classicalSmall) }
            }
        }
        .task(id: d.id) { if d.watch || d.reveal != nil { return }; try? await Task.sleep(nanoseconds: 7_000_000_000); if model.doneNote?.id == d.id { model.doneNote = nil } }
    }
}
