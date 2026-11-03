// The New Design's scenes of a looping video, in playing order. A slot is one window on the Scenes list: its own scene idea, picture and loop clip,
// blank until you make or add them. What the video plays is still decided by the older fields (each song's clip, the list of clips in the order),
// which every sync writes from the slots, so the original design and the video maker read the same project.
//   • At each song change: one slot per song (songs that already shared a clip stay in one slot, which can be separated), tied to its songs.
//   • Every few minutes: the slots you add or take away, played in this order and then again.
//   • One clip: one slot.
// While a slot is selected its idea, picture, clip and motion are also the project's own scene, picture, clip and motion, so every existing button
// works on it; `syncSlots` copies them back into the slot.
import Foundation

public struct LoopSlot: Codable, Equatable, Identifiable {
    public var id = UUID().uuidString
    public var idea = ""                 // what this scene shows
    public var motion = ""               // what moves in its clip
    public var picture: String?
    public var clip: String?
    public var drawn: String?            // the words its picture was drawn from
    public var songs: [String] = []      // track ids it plays under (At each song change)
    public init() {}
    enum CodingKeys: String, CodingKey { case id, idea, motion, picture, clip, drawn, songs }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        idea = try c.decodeIfPresent(String.self, forKey: .idea) ?? ""; motion = try c.decodeIfPresent(String.self, forKey: .motion) ?? ""
        picture = try c.decodeIfPresent(String.self, forKey: .picture); clip = try c.decodeIfPresent(String.self, forKey: .clip)
        drawn = try c.decodeIfPresent(String.self, forKey: .drawn); songs = try c.decodeIfPresent([String].self, forKey: .songs) ?? []
    }
    public var isBlank: Bool { clip == nil && picture == nil && idea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

extension LoopVideo {
    public static let startingTimeSlots = 4

    public static func slots(_ p: LoopProject) -> [LoopSlot] { p.sceneSlots[p.sceneChange.rawValue] ?? [] }

    /// Keeps the slots, the songs' clips and the list of clips in step, and makes sure a slot is selected. Returns the selected slot's id.
    /// `focus` is the slot the project's own scene, picture, clip and motion belong to right now.
    @discardableResult
    public static func syncSlots(_ p: inout LoopProject, focus: String?, adoptExternal: Bool = false) -> String? {
        let key = p.sceneChange.rawValue
        var slots = p.sceneSlots[key] ?? []
        let seeding = slots.isEmpty
        // 1. what the project says about the selected slot belongs to it
        if let f = focus, let i = slots.firstIndex(where: { $0.id == f }) {
            slots[i].idea = p.scene; slots[i].motion = p.motion; slots[i].picture = p.picture; slots[i].clip = p.clip; slots[i].drawn = p.sceneDrawn
        }
        let focusID = focus.flatMap { f in slots.contains { $0.id == f } ? f : nil }
        // 2. the structure for this way of changing scene
        switch p.sceneChange {
        case .songs: slots = songSlots(p, existing: slots, focus: focusID, seeding: seeding, adopt: adoptExternal)
        case .time: slots = timeSlots(p, existing: slots, focus: focusID, seeding: seeding, adopt: adoptExternal)
        case .never:
            var s = slots.first ?? LoopSlot()
            if seeding || focusID == nil { s.clip = p.clip }
            slots = [s]
        }
        if seeding { carryOver(p, into: &slots) }
        // 3. the older fields the video maker reads
        switch p.sceneChange {
        case .songs:
            for s in slots { for id in s.songs { if let k = p.tracks.firstIndex(where: { $0.id == id }) { p.tracks[k].clip = s.clip } } }
            p.sceneClips = unique(slots.compactMap(\.clip)).filter { p.clips.contains($0) }
        case .time:
            p.sceneClips = unique(slots.compactMap(\.clip)).filter { p.clips.contains($0) }
        case .never: break
        }
        p.sceneSlots[key] = slots
        if let f = focusID { return f }
        let pick = slots.first(where: { $0.clip != nil && $0.clip == p.clip }) ?? slots.first(where: { $0.clip != nil }) ?? slots.first
        if let pick { load(&p, pick) }
        return pick?.id
    }

    /// Makes a slot the one the project's own scene, picture, clip and motion describe.
    static func load(_ p: inout LoopProject, _ s: LoopSlot) {
        p.scene = s.idea; p.motion = s.motion; p.picture = s.picture; p.clip = s.clip; p.sceneDrawn = s.drawn
        if let pic = s.picture, !s.motion.isEmpty { p.motionByPicture[pic] = s.motion }
    }

    /// Selects another slot: the one left keeps what was made in it, the new one's scene, picture and clip become the project's.
    public static func selectSlot(_ p: inout LoopProject, from: String?, to id: String) {
        syncSlots(&p, focus: from)
        if let s = slots(p).first(where: { $0.id == id }) { load(&p, s) }
    }

    /// A project that has to play: its clip in use is never empty while a scene has one. Called when leaving the Scenes stage.
    public static func selectFirstFilled(_ p: inout LoopProject, from: String?) {
        syncSlots(&p, focus: from)
        let all = slots(p)
        if let s = all.first(where: { $0.clip != nil && $0.clip == p.clip }) ?? all.first(where: { $0.clip != nil }) { load(&p, s) }
    }

    // MARK: songs
    static func songSlots(_ p: LoopProject, existing: [LoopSlot], focus: String?, seeding: Bool, adopt: Bool) -> [LoopSlot] {
        let resolved = songClips(p)
        var out: [LoopSlot] = []
        var k = 0
        while k < p.tracks.count {
            let t = p.tracks[k]
            if let s = existing.first(where: { $0.songs.contains(t.id) }), !out.contains(where: { $0.id == s.id }) {
                var n = 1
                while k + n < p.tracks.count && s.songs.contains(p.tracks[k + n].id) { n += 1 }
                var s2 = s; s2.songs = p.tracks[k..<(k + n)].map(\.id)
                // a clip chosen for its songs elsewhere (the original design) is adopted, unless this scene is the one being edited
                if adopt, s2.id != focus {
                    let chosen = Set(p.tracks[k..<(k + n)].compactMap(\.clip).filter { p.clips.contains($0) })
                    if chosen.count == 1, let only = chosen.first, s2.clip != only { s2.clip = only }
                }
                if let c = s2.clip, !p.clips.contains(c) { s2.clip = nil }
                out.append(s2); k += n; continue
            }
            var s = LoopSlot(); s.songs = [t.id]
            if seeding {
                // a clip chosen for a song stays with it (songs sharing a clip stay together); a song on Auto takes the next clip in turn only the first time that clip
                // comes up, and a blank scene borrows the rest, so the video plays exactly as before
                if let c = t.clip, p.clips.contains(c) {
                    s.clip = c
                    if let last = out.last, last.clip == c, last.songs.last == p.tracks[k - 1].id, k > 0 { out[out.count - 1].songs.append(t.id); k += 1; continue }
                } else if let c = resolved[k].clip, !out.contains(where: { $0.clip == c }) { s.clip = c }
            } else if adopt, let c = t.clip, p.clips.contains(c) { s.clip = c }
            out.append(s); k += 1
        }
        return out
    }

    // MARK: time
    static func timeSlots(_ p: LoopProject, existing: [LoopSlot], focus: String?, seeding: Bool, adopt: Bool) -> [LoopSlot] {
        let listed = unique(p.sceneClips.filter { p.clips.contains($0) })
        if seeding {
            var out = (listed.isEmpty ? (p.clip.map { [$0] } ?? []) : listed).map { c -> LoopSlot in var s = LoopSlot(); s.clip = c; return s }
            while out.count < startingTimeSlots { out.append(LoopSlot()) }
            return out
        }
        var out = existing
        for i in out.indices where out[i].id != focus && (adopt || !p.clips.contains(out[i].clip ?? "")) {
            if let c = out[i].clip, !listed.contains(c), !listed.isEmpty || !p.clips.contains(c) { out[i].clip = nil }     // taken out of the list elsewhere
        }
        for c in listed where adopt && !out.contains(where: { $0.clip == c }) {                                                   // added elsewhere
            if let blank = out.firstIndex(where: { $0.isBlank && $0.id != focus }) { out[blank].clip = c } else { var s = LoopSlot(); s.clip = c; out.append(s) }
        }
        return out
    }

    /// The first time slots are made: the scene the project already describes goes to its clip's slot, and what another way of changing scene knew about a clip comes along.
    static func carryOver(_ p: LoopProject, into slots: inout [LoopSlot]) {
        let others = p.sceneSlots.filter { $0.key != p.sceneChange.rawValue }.flatMap(\.value)
        for i in slots.indices {
            if let c = slots[i].clip {
                if let o = others.first(where: { $0.clip == c && !$0.isBlank }) { slots[i].idea = o.idea; slots[i].motion = o.motion; slots[i].picture = o.picture; slots[i].drawn = o.drawn }
                else if c == p.clip { slots[i].idea = p.scene; slots[i].motion = p.motion; slots[i].picture = p.picture; slots[i].drawn = p.sceneDrawn }
            }
        }
    }

    static func unique(_ l: [String]) -> [String] { var seen = Set<String>(); return l.filter { seen.insert($0).inserted } }

    // MARK: editing the list
    /// Every few minutes: one more blank scene at the end.
    public static func addSlot(_ p: inout LoopProject, focus: String?) {
        syncSlots(&p, focus: focus)
        guard p.sceneChange == .time else { return }
        p.sceneSlots["time", default: []].append(LoopSlot())
    }
    /// Every few minutes: takes a scene out of the list (its clip stays with the project). At least one stays.
    public static func removeSlot(_ p: inout LoopProject, id: String, focus: String?) {
        syncSlots(&p, focus: focus)
        guard p.sceneChange == .time, var l = p.sceneSlots["time"], l.count > 1, let i = l.firstIndex(where: { $0.id == id }) else { return }
        l.remove(at: i); p.sceneSlots["time"] = l
        syncSlots(&p, focus: focus == id ? nil : focus)
    }
    /// Makes a scene blank again (its songs go back to borrowing); the files stay in the project.
    public static func clearSlot(_ p: inout LoopProject, id: String, focus: String?) {
        syncSlots(&p, focus: focus)
        let key = p.sceneChange.rawValue
        guard var l = p.sceneSlots[key], let i = l.firstIndex(where: { $0.id == id }) else { return }
        l[i].idea = ""; l[i].motion = ""; l[i].picture = nil; l[i].clip = nil; l[i].drawn = nil
        p.sceneSlots[key] = l
        if focus == id { load(&p, l[i]) }
        syncSlots(&p, focus: focus)
    }
    /// At each song change: gives every song of a shared scene its own scene (the first keeps the clip).
    public static func separateSlot(_ p: inout LoopProject, id: String, focus: String?) {
        syncSlots(&p, focus: focus)
        guard p.sceneChange == .songs, var l = p.sceneSlots["songs"], let i = l.firstIndex(where: { $0.id == id }), l[i].songs.count > 1 else { return }
        let extra = l[i].songs.dropFirst().map { sid -> LoopSlot in var s = LoopSlot(); s.songs = [sid]; return s }
        l[i].songs = [l[i].songs[0]]
        l.insert(contentsOf: extra, at: i + 1)
        p.sceneSlots["songs"] = l
        syncSlots(&p, focus: focus)
    }
    /// Moves a scene to a place in the list. At each song change its songs move with it (the scene and its songs are tied together).
    public static func moveSlot(_ p: inout LoopProject, id: String, to index: Int, focus: String?) {
        syncSlots(&p, focus: focus)
        let key = p.sceneChange.rawValue
        guard var l = p.sceneSlots[key], let i = l.firstIndex(where: { $0.id == id }) else { return }
        let s = l.remove(at: i)
        l.insert(s, at: max(0, min(index, l.count)))
        p.sceneSlots[key] = l
        if p.sceneChange == .songs {
            let order = l.flatMap(\.songs)
            p.tracks.sort { a, b in (order.firstIndex(of: a.id) ?? 0) < (order.firstIndex(of: b.id) ?? 0) }
            if let f = p.tracks.first { p.songFile = f.file; p.songSeconds = f.seconds }
        }
        syncSlots(&p, focus: focus)
    }
    /// How many scenes have no picture or clip yet.
    public static func blankSlots(_ p: LoopProject) -> (blank: Int, total: Int) {
        let l = slots(p); return (l.filter { $0.clip == nil }.count, l.count)
    }
}
