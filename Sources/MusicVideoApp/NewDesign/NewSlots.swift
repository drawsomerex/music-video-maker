// The New Design's scene list of a looping video, on the model: select a scene, keep the list in step with the project, edit the list.
import SwiftUI
import MVCore

extension AppModel {
    /// Brings the scenes in step with the songs and clips (and what the selected scene now holds). `adopt` also takes over what the original design changed.
    func slotSync(adopt: Bool = false) {
        guard var p = loopProject, loopDir != nil else { return }
        let old = p
        let f = LoopVideo.syncSlots(&p, focus: loopSlot, adoptExternal: adopt)
        if loopSlot != f { loopSlot = f }
        if p != old { loopProject = p; planRevision += 1; persistLoop() }
    }
    func slotSelect(_ id: String) {
        guard loopJob == nil else { return }
        let from = loopSlot
        editLoop { LoopVideo.selectSlot(&$0, from: from, to: id) }
        loopSlot = id
        if let c = loopProject?.clip, let u = loopPreviewURL(for: c), !FileManager.default.fileExists(atPath: u.path) { loopMakePreview(c) }
    }
    func slotEdit(_ f: @escaping (inout LoopProject, String?) -> Void) {
        guard loopJob == nil else { return }
        slotSync()
        let focus = loopSlot
        editLoop { f(&$0, focus) }
        slotSync()
    }
    /// Leaving the Scenes stage: a scene that has a clip is the one in use again, so Shorts, thumbnails and previews always have one.
    func slotLeave() {
        guard loopJob == nil, loopProject != nil else { return }
        let from = loopSlot
        editLoop { LoopVideo.selectFirstFilled(&$0, from: from) }
        loopSlot = nil
    }
    /// A blank scene: its picture is drawn as the next scene of the previous scene's picture (the same place, building or subject).
    func slotDrawFromPrevious() {
        guard let p = loopProject, let id = loopSlot, let i = LoopVideo.slots(p).firstIndex(where: { $0.id == id }), i > 0,
              let prev = LoopVideo.slots(p)[..<i].last(where: { $0.picture != nil }) else { return }
        editLoop { q in q.picture = prev.picture; q.motion = prev.motion }
        loopMakeNextPicture()
    }
}
