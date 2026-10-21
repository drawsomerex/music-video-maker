# Audit of the updates since 1.5.4 (written 2026-10-21)

Plain-language record of what changed in each release and why, followed by a sweep for bugs, speed-ups and workflow ideas.
Nothing in "Findings" has been fixed yet; the owner decides what to fix.

## 1. What changed, release by release

| Release | What changed | Why it was changed |
|---|---|---|
| **1.5.0** | Report-a-problem window (relay to GitHub Issues); video clips instead of pictures (drag in an MP4/MOV, plays and loops); picture ideas always bright; faster automatic camera. | You wanted users to report bugs and see replies; to use your own video clips; no gloomy pictures; clearly visible camera motion. |
| **1.5.1–1.5.4** | Start/end trim panel for imported clips (rebuilt twice for clarity and window size); trim handles follow the mouse (a drag bug); a repeating clip dissolves into its start; camera made more dramatic. | "The video controls are awful"; handles ran away to the end; "a hard cut when it loops". |
| **1.6.0** | The Song page "Divide into parts" became a timeline: *Listen to the song first*, one picture per verse and per music break (music break over 40 s split, under 4 s joined), brackets removed from lyrics, "A picture every N s" stepper removed, "Add pictures from a folder" removed. | Your request: divide by lyrics **and** music breaks, bright-line rules, no Suno tags in captions. |
| **1.6.1** (another AI) | Timeline editor rebuilt: undo/redo, drafts, Shorts editing from the Song page, bug-report visibility, release-tag protection, version backups. | The other AI's audit and release; it rewrote much of the timeline code. |
| **1.6.2** | All lyrics visible again; a split may only ever add one cut (refused otherwise); drafts saved on disk; Undo bar; regression test. | Your bug: "Start new picture here deleted all my other cuts" and "there needs to be lyrics visible". |
| **1.7.0** | Story logic pass by the local model after ideas / "Another idea"; style guide reference picture; HeyGen clips (single, whole-section back to back, preview, realism check, cost tracking); true-to-scale draggable timeline for pictures and Shorts on both pages. | Your plan: forward-moving ideas, consistent look, optional HeyGen video, draggable timeline. |
| **1.7.1** | New clips used straight away; automatic camera travels subject to subject. | "Default to Use this clip"; "Ken Burns should move from subject to subject at a decent pace". |
| **1.7.2** | Camera makes one journey (no repeated back-and-forth); your own camera move is as large as the picture allows. | "Never back and forth and back again"; "custom move as big as possible". |
| **1.8.0** | Every idea has two focal points; camera goes focal point 1 to 2; the same move runs over a clip; shared Pictures folder with date-project-number names. | Your request for two focal points and a trackable picture folder. |
| **1.8.1** | New picture = new perspective on the previous scene (previous picture sent as a reference); neighbouring ideas must look dramatically different. | "It's still using the old picture"; "must be dramatically different". |

## 2. Why controls seem to have disappeared (verified in the code)

* Imported clips still have the trim panel, but **HeyGen clips never had one**: no start/end, no "Play this part".
* While a clip is in use, **the camera controls ("I choose the move", "Aim for me") are hidden**.
* Imported clips **repeat by default** (with a dissolve). Generated clips don't repeat but **have no repeat or hold option at all**.
* 1.8.0 added a camera move **over the clip** itself (zoomed, soft) that you did not ask for after the clip.

## 3. Findings of the sweep

### A. Bugs (can lose work or money)
1. **A paid HeyGen job is lost if the app quits mid-clip.** The job id is only written after the clip finishes. *Money lost; clip unrecoverable.*
2. **Splitting a picture duplicates its video clips into both halves**; both halves then play the same clip.
3. **Joining pictures drops the right picture's clips** (paid media silently disappears from the plan).
4. **Undo can hide paid video clips and under-report the video cost** (Undo restores old copies of the plan; clips and `totalVideoCostUSD` are not carried over like pictures are).
5. **A Short that starts in the middle of a section with a clip plays the clip from its beginning.** (The clip offset is not shifted for Shorts.)
6. **Clips and last-frame files are never cleaned up** when sections are joined or deleted (disk grows; pictures are cleaned, clips are not).
7. **`release.sh` publishes even when `git merge` left conflict markers** (happened once: v1.8.0 notes were wrong; fixed by hand).

### B. Behaviour that does not match what you asked
8. **Clip default**: imported clips loop; the Ken Burns-on-last-frame default you asked for is not implemented for them.
9. **"Make video clips for all pictures"** (agreed in the plan with a total price) was **never built**.
10. **Picture library is not back-filled**: pictures from songs made before 1.8.0 are not in the Pictures folder.

### C. Speed and efficiency
11. **The live preview rebuilds whenever any cost number changes** (the preview signature hashes the whole plan, including costs and notes), causing needless re-renders after every picture, clip or check.
12. **Planning is slower**: up to two extra local-model calls per picture (focal points + story check). The focal points now come from the first writing call, so only missing ones are asked for; a re-run on a long song should be measured.
13. **The timeline redraws every lyric line on each drag step**; fine for songs with ~60 lines, heavy beyond ~300.
14. **Video frames are decoded one at a time per output frame** (acceptable for a few clips; a song of 36 clips at 30 fps would be slow to render).

### D. Workflow suggestions (not bugs)
15. **Top-of-window progress banner for every long task** (requested).
16. **Timeline takes about 230 px of height on the Pictures page**; on a small laptop screen it should start collapsed.
17. **Trim and repeat/hold options** for generated clips (see section 2).
18. **A single "cost so far / cost to finish" line** for pictures **and** clips, with the price of "Make everything" before you press it.
19. **Back-fill / export button for the Pictures folder**; optional "make the Pictures folder the only copy".
20. **A one-page "what will this cost" summary** before Plan my video / Make all.

## 4. Not worth doing now
* Making the cloud focal-point and realism checks run on the local model (the local model has no vision).
* Splitting the 1,300-line `AppModel.swift` into smaller files (risky refactor, no user-visible gain).
