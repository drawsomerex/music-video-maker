// Jev, the quick decision model, as the app uses it: advice before a paid clip and a plain sentence under an error. Both designs share this code.
import SwiftUI
import MVCore

extension AppModel {
    /// A new error message: works out the one-sentence advice first (a moment at most), then lets the box open.
    func errorChanged(old: String?) {
        guard let message = errorMessage else { triageTask?.cancel(); errorAdvice = nil; errorReady = true; return }
        if message == old, errorReady { return }
        errorAdvice = nil
        triageTask?.cancel()
        let key = config.effectiveOpenRouterKey, use = config.useDecisionModel
        guard use, !key.isEmpty else { errorAdvice = ErrorTriage.rule(message).flatMap(ErrorTriage.advice); errorReady = true; return }
        errorReady = false
        triageTask = Task { [weak self] in
            let advice = await ErrorTriage.advice(for: message, apiKey: key)
            guard !Task.isCancelled, let self, self.errorMessage == message else { return }
            self.errorAdvice = advice; self.errorReady = true
        }
    }

    /// Before a clip order is confirmed: asks Jev whether the scenes will animate well, keeps what it found in `clipAdvice` for the dialog, then goes on.
    /// Quick (a second or two at most); when Jev is off or unreachable it simply goes on.
    func checkClipsThen(_ items: [ClipRisk.Item], kind: ClipRisk.Kind, _ go: @escaping () -> Void) {
        clipAdvice = nil
        let key = config.effectiveOpenRouterKey
        let list = items.filter { !$0.idea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard config.useDecisionModel, !key.isEmpty, !list.isEmpty else { go(); return }
        Task { [weak self] in
            let flags = await ClipRisk.check(list, kind: kind, apiKey: key)
            self?.clipAdvice = ClipRisk.advice(flags)
            go()
        }
    }

    /// The scenes of a music video's pictures (-1 is the title card) as the clip check reads them.
    func clipRiskItems(_ sections: [Int]) -> [ClipRisk.Item] {
        guard let p = plan else { return [] }
        return sections.compactMap { i in
            if i < 0 { return ClipRisk.Item(label: "The title card", idea: p.intro.prompt) }
            guard p.sections.indices.contains(i) else { return nil }
            return ClipRisk.Item(label: "Picture \(i + 1)", idea: p.sections[i].prompt)
        }
    }
    var clipAdviceNote: String { clipAdvice.map { "\n\n" + $0 } ?? "" }
}
