// Always-visible picture costs: what has been spent, and what drawing the blank pictures would cost.
import SwiftUI
import MVCore

struct CostBar: View {
    @EnvironmentObject var model: AppModel
    @State private var all: (usd: Double, pictures: Int, songs: Int) = (0, 0, 0)

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(compact: false)
            row(compact: true)
        }
        .padding(.horizontal, 20).padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(Color.green.opacity(0.10))
        .overlay(alignment: .bottom) { Divider() }
        .task(id: "\(model.plan?.totalGenerationCostUSD ?? 0)|\(model.plan?.totalVideoCostUSD ?? 0)|\(model.config.projectsFolder)|\(model.busy)") {
            let root = model.config.projectsRoot
            all = await Task.detached(priority: .utility) { Pipeline.totalSpent(in: root) }.value
        }
    }

    func row(compact: Bool) -> some View {
        HStack(spacing: compact ? 12 : 22) {
            Image(systemName: "dollarsign.circle.fill").foregroundStyle(.green)
            if model.stage == .loop, let lp = model.loopProject {
                item(compact ? "This video" : "Spent on this looping video", OpenRouter.formatUSD(lp.imagesUSD + lp.videoUSD), help: "What the picture and the loop clip for this looping video have cost (the cost OpenRouter reported).")
            } else if let p = model.plan {
                item(compact ? "This song" : "Spent on this song", OpenRouter.formatUSD(p.totalGenerationCostUSD), detail: p.imagesGeneratedCount > 0 ? "\(p.imagesGeneratedCount) pictures" : nil,
                     help: "What drawing pictures for this song has cost so far.")
                if p.totalVideoCostUSD > 0 {
                    item(compact ? "Video" : "Video clips", OpenRouter.formatUSD(p.totalVideoCostUSD), detail: nil, help: "What the video clips for this song have cost so far (the cost OpenRouter reported).")
                }
                let blank = model.missing.count
                item(blank == 0 ? "Blank pictures" : (compact ? "To draw \(blank) blank" : "To draw the \(blank) blank pictures"), blank == 0 ? "none" : "≈ " + OpenRouter.formatUSD(model.missingImagesCostUSD),
                     help: "The estimated cost of drawing every picture that is still blank, at about \(OpenRouter.formatUSD(model.perImageCostUSD)) each.")
            }
            item(compact ? "All songs" : "All songs together", OpenRouter.formatUSD(all.usd), detail: all.songs > 1 ? "\(all.songs) songs" : nil,
                 help: "Everything you have spent on pictures and video clips across all your songs. It is kept in a permanent record, so it never goes down: not after an update, not when a song is moved or deleted.")
            if model.hasOpenRouterKey, let rem = model.openRouterCredits {
                item(compact ? "Credit" : "Credit left", OpenRouter.formatCredits(rem), tint: rem < model.missingImagesCostUSD ? .orange : .green,
                     help: "What is left on your OpenRouter account. It turns orange when it is not enough to draw all the blank pictures.")
            }
            Spacer(minLength: 0)
        }
        .font(.callout)
    }

    func item(_ title: String, _ value: String, detail: String? = nil, tint: Color = .primary, help: String) -> some View {
        HStack(spacing: 5) {
            Text(title + ":").foregroundStyle(.secondary).lineLimit(1).fixedSize()
            Text(value).font(.callout.monospacedDigit().weight(.semibold)).foregroundStyle(tint).lineLimit(1).fixedSize()
            if let detail { Text("(\(detail))").font(.caption).foregroundStyle(.secondary).lineLimit(1).fixedSize() }
        }
        .help(help)
    }
}
