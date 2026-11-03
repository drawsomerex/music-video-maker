// The New Design: one workspace for both kinds of video. A Projects home, then numbered stages under one 52 px bar.
// It shares the same model and actions as the original design; only the screens differ. Turned on in Settings (or View menu).
import SwiftUI
import MVCore

enum NewDesign {
    static let key = "newDesign"
}

/// Where the New Design window is: the home, or one of the four stages (a looping video's stages are Music, Scenes, Shorts, Export).
@MainActor final class NewDesignState: ObservableObject {
    enum Route: Int { case home, song, pictures, shorts, export }
    @Published var route: Route = .home
    @Published var activityOpen = false
}

struct NewRootView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var updater: Updater
    @StateObject private var nd = NewDesignState()
    init() { _ = Classical.registered }

    var body: some View {
        ZStack {
            Classical.bg.ignoresSafeArea()
            if model.needsNativeSetup { NewSetupView() } else {
                VStack(spacing: 0) {
                    NewTopBar()
                    Hairline()
                    HStack(spacing: 0) {
                        content.disabled(updater.isInstalling)
                        if nd.activityOpen { NewActivityPanel() }
                    }
                }
            }
        }
        .environmentObject(nd)
        .environment(\.colorScheme, .light)
        .tint(Classical.accent)
        .font(Classical.body(13))
        .background(NewWindowStyle())
        .onAppear { if model.stage == .plan || model.stage == .loop { nd.route = .pictures } else if model.stage == .done || model.stage == .rendering { nd.route = .export } }
        .onChange(of: model.hasActivity) { _, on in if on { nd.activityOpen = true } }
        .onChange(of: model.stage) { _, s in
            switch s {
            case .plan where nd.route == .home || nd.route == .song: nd.route = .pictures
            case .rendering, .done: nd.route = .export
            default: break
            }
        }
        .sheet(item: $model.pictureFit) { PictureFitSheet(req: $0).environmentObject(model) }
        .modifier(AutoAskModifier())
    }

    @ViewBuilder var content: some View {
        switch nd.route {
        case .home: NewHomeView()
        case .song: NewSongStage()
        case .pictures: NewPicturesStage()
        case .shorts: NewShortsStage()
        case .export: NewExportStage()
        }
    }
}

// MARK: the one bar on top

struct NewTopBar: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var updater: Updater
    @EnvironmentObject var nd: NewDesignState
    @Environment(\.openSettings) private var openSettings
    @State private var allSpent: Double = 0

    var isLoop: Bool { model.stage == .loop || model.loopProject != nil }
    var projectTitle: String { isLoop ? (model.loopProject?.title ?? "New looping video") : (model.plan?.title ?? (model.title.isEmpty ? "New music video" : model.title)) }
    var stageNames: [String] { isLoop ? ["Music", "Scenes", "Shorts", "Export"] : ["Song", "Pictures", "Shorts", "Export"] }
    var hasWork: Bool { isLoop ? model.loopProject != nil : model.plan != nil }
    var thisSpent: Double {
        if isLoop, let lp = model.loopProject { return lp.imagesUSD + lp.videoUSD }
        return (model.plan?.totalGenerationCostUSD ?? 0) + (model.plan?.totalVideoCostUSD ?? 0)
    }

    var body: some View {
        HStack(spacing: 14) {
            if nd.route == .home {
                Text("Music Video Maker").font(Classical.heading(20)).foregroundStyle(Classical.text).padding(.leading, 4)
            } else {
                Button { goHome() } label: { HStack(spacing: 5) { Image(systemName: "square.grid.2x2").font(.system(size: 11)); Text("Projects") }.font(Classical.body(13)).foregroundStyle(Classical.neutral700) }
                    .buttonStyle(.plain)
                    .padding(.leading, 4).help("All your projects (Command-O)")
                Text("/").foregroundStyle(Classical.neutral500)
                Text(projectTitle).font(Classical.heading(18)).foregroundStyle(Classical.text).lineLimit(1)
            }
            Spacer(minLength: 8)
            if nd.route != .home { stageTabs }
            Spacer(minLength: 8)
            if model.hasActivity {
                Button { nd.activityOpen.toggle() } label: { Text("\(max(1, model.activityItems.count + (model.directorRun == nil ? 0 : 1))) running") }.buttonStyle(.classicalSmall)
                    .help("Show or hide Activity: everything that is running.")
            }
            costPill
            if let r = updater.available, nd.route == .home || true {
                Button { updater.showAvailable = true } label: { Text("Update \(r.version)") }.buttonStyle(.classicalSmall).help("A new version is ready. Updating takes about a minute and keeps all your work.")
            }
            Button { openSettings() } label: { Image(systemName: "gearshape") }.buttonStyle(.plain).foregroundStyle(Classical.neutral700).help("Settings")
            Button { model.helpScreen = model.screenName; model.showHelp = true } label: { Image(systemName: "questionmark.circle") }.buttonStyle(.plain).foregroundStyle(Classical.neutral700)
                .help("Ask a question in your own words, or read the guide. The helper knows what is on your screen right now.")
        }
        .padding(.horizontal, 16).frame(height: 52)
        .background(Classical.bg)
        .task(id: "\(model.config.projectsFolder)|\(model.busy)|\(thisSpent)") {
            let root = model.config.projectsRoot
            allSpent = await Task.detached(priority: .utility) { Pipeline.totalSpent(in: root).usd }.value
        }
    }

    func goHome() { nd.route = .home }

    var stageTabs: some View {
        HStack(spacing: 18) {
            ForEach(Array(stageNames.enumerated()), id: \.offset) { i, name in
                let r = NewDesignState.Route(rawValue: i + 1) ?? .song
                let current = nd.route == r
                let enabled = i == 0 || hasWork
                let done = enabled && r.rawValue < nd.route.rawValue
                Button { if enabled { nd.route = r } } label: {
                    HStack(spacing: 5) {
                        ZStack {
                            Circle().stroke(current ? Classical.accent : Classical.neutral300, lineWidth: 1).frame(width: 17, height: 17)
                            if done { Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Classical.accent700) }
                            else { Text("\(i + 1)").font(Classical.body(10)).foregroundStyle(current ? Classical.accent700 : Classical.neutral600) }
                        }
                        Text(name).font(Classical.body(13, weight: current ? .semibold : .regular)).foregroundStyle(current ? Classical.text : Classical.neutral600).lineLimit(1).fixedSize()
                    }
                    .padding(.vertical, 4)
                    .overlay(alignment: .bottom) { Rectangle().fill(current ? Classical.accent : .clear).frame(height: 2).offset(y: 9) }
                }.buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.5)
            }
        }
    }

    var costPill: some View {
        HStack(spacing: 10) {
            if nd.route == .home {
                meter("All projects", OpenRouter.formatUSD(allSpent))
            } else {
                meter(isLoop ? "This video" : "This song", OpenRouter.formatUSD(thisSpent))
            }
            if model.hasOpenRouterKey, let rem = model.openRouterCredits {
                VHairline().frame(height: 14)
                meter("Credit", OpenRouter.formatCredits(rem))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Classical.divider, lineWidth: 1))
        .help("What pictures and clips have cost. “Credit” is what is left on your OpenRouter account.")
    }
    func meter(_ k: String, _ v: String) -> some View {
        HStack(spacing: 5) { Text(k).font(Classical.body(11)).foregroundStyle(Classical.neutral600); Text(v).font(Classical.body(12, weight: .semibold).monospacedDigit()).foregroundStyle(Classical.text) }
    }
}


/// A light window whose title strip blends into the page. Restores the normal window when the design is switched off.
struct NewWindowStyle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { Self.apply(v.window, on: true) }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) { DispatchQueue.main.async { Self.apply(v.window, on: true) } }
    static func dismantleNSView(_ v: NSView, coordinator: ()) { Self.apply(v.window, on: false) }
    static func apply(_ w: NSWindow?, on: Bool) {
        NSApp.appearance = on ? NSAppearance(named: .aqua) : nil
        guard let w else { return }
        w.appearance = on ? NSAppearance(named: .aqua) : nil
        w.titlebarAppearsTransparent = on
        w.titleVisibility = on ? .hidden : .visible
        w.backgroundColor = on ? NSColor(srgbRed: 0xF3 / 255.0, green: 0xF2 / 255.0, blue: 0xF2 / 255.0, alpha: 1) : nil
    }
}
