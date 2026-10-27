// Cheap pre-export checks shared by the UI and renderers. No network requests or paid repairs.
import Foundation
import ImageIO

public struct ExportHealth {
    public var errors: [String] = []
    public var warnings: [String] = []
    public var text: String { (errors.map { "Needs attention: " + $0 } + warnings.map { "Note: " + $0 }).joined(separator: "\n") }
    public func requireReady() throws { if !errors.isEmpty { throw MVError(text) } }
    public static func music(_ plan: Plan, work: URL, height: Int = 1080, short: ShortClip? = nil) -> ExportHealth {
        var result = ExportHealth()
        if !FileManager.default.fileExists(atPath: Pipeline.audioURL(plan, work: work).path) { result.errors.append("The song file is missing. Restore it before exporting.") }
        let media = short.map { FrameComposer.clip(plan, to: $0).sections } ?? ([plan.intro] + plan.sections)
        for (index, section) in TimelineEditor.renderSections(media).enumerated() {
            let label = index == 0 ? "Title card" : "Picture \(index)"
            if section.useClips && !section.clips.isEmpty {
                for clip in section.clips { result.check(clip.file, work: work, label: label) }
            } else if let candidate = section.selectedCandidate {
                if let file = candidate.videoFile { result.check(file, work: work, label: label) }
                else if let file = candidate.fullFile {
                    result.check(file, work: work, label: label)
                    if let source = CGImageSourceCreateWithURL(work.appendingPathComponent(file) as CFURL, nil),
                       let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any], let pixels = props[kCGImagePropertyPixelHeight] as? Int, pixels < height {
                        result.warnings.append("\(label) has \(pixels) source pixels in height; \(height)p output will enlarge it.")
                    }
                }
            }
        }
        if !Pipeline.pendingClipJobs(work: work).isEmpty { result.warnings.append("A paid clip is pending. This export uses the currently approved media.") }
        return result
    }
    public static func loop(_ plan: LoopProject, work: URL) -> ExportHealth {
        var result = ExportHealth()
        for track in plan.tracks { result.check(track.file, work: work, label: "Song \(track.title)") }
        for clip in LoopVideo.sceneClips(plan) { result.check(clip, work: work, label: "Loop scene") }
        if plan.clip == nil { result.errors.append("Make or add the loop clip first.") }
        if plan.pendingJob != nil || !LoopVideo.pendingLoopJobs(work).isEmpty { result.warnings.append("A paid clip is pending. This export uses the current scene list.") }
        return result
    }
    private mutating func check(_ relative: String, work: URL, label: String) {
        let file = work.appendingPathComponent(relative).standardizedFileURL.resolvingSymlinksInPath()
        let root = work.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        if !file.path.hasPrefix(root) || !FileManager.default.fileExists(atPath: file.path) { errors.append("\(label): a referenced media file is missing or outside this project (\(relative)).") }
    }
}
