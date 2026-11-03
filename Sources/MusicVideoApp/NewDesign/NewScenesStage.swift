// Stage 2 · Scenes for a looping video (design 2g): the same shell, Look and director as a music video's Pictures stage.
import SwiftUI
import MVCore

struct NewScenesStage: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var nd: NewDesignState
    @State private var showLook = false
    @State private var confirmClip = false
    var p: LoopProject { model.loopProject ?? LoopProject() }
    var working: Bool { model.loopJob != nil }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { showLook = true } label: { HStack(spacing: 5) { Image(systemName: "paintpalette").font(.system(size: 11)); Text("Look") } }.buttonStyle(.classicalSmall)
                    .help("Art style, quality, brightness, weather, time of day, shot, the picture to base it on, cloudless sky and what moves.")
                Menu {
                    Button("Direct the rest (≈ \(OpenRouter.formatUSD(model.loopAutoPrice)))") { model.loopAutoAsk() }
                    Button("Plan with the director, then I approve…") { model.loopDirectorPlan() }
                } label: { HStack(spacing: 5) { Image(systemName: "wand.and.stars").font(.system(size: 11)); Text("Director…") } }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().font(Classical.body(12)).padding(.horizontal, 10).padding(.vertical, 4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Classical.neutral300, lineWidth: 1)).disabled(working || p.tracks.isEmpty)
                Spacer()
            }.padding(.horizontal, 20).padding(.vertical, 9).background(Classical.bg)
            Hairline()
            LoopView(part: .scenes)
            CFooter {
                let n = p.clips.count
                Text(n == 0 ? "No loop clip yet" : "\(n) loop clip\(n == 1 ? "" : "s") ready").font(Classical.body(12)).foregroundStyle(Classical.neutral700)
            } right: {
                Button { model.loopPreview(.start) } label: { Text("▷ Preview") }.buttonStyle(.classical).disabled(working || p.clip == nil || p.tracks.isEmpty)
                Button("Continue to Shorts →") { nd.route = .shorts }.buttonStyle(.classicalPrimary)
            }
        }
        .sheet(isPresented: $showLook) {
            VStack(spacing: 0) {
                LoopView(part: .look)
                CFooter { Text("Same Look panel, versions and picture check as music videos.").font(Classical.body(11)).foregroundStyle(Classical.neutral600) } right: { Button("Done") { showLook = false }.buttonStyle(.classicalPrimary).keyboardShortcut(.defaultAction) }
            }.frame(width: 640, height: 720).background(Classical.bg).environment(\.colorScheme, .light).environmentObject(model)
        }
    }
}
