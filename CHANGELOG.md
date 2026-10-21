# Changelog

All notable changes to Music Video Maker. Newest first. **Add every user-visible change under `[Unreleased]` as you make it** —
`./release.sh` turns that section into the GitHub release notes (shown to users in the in-app "Update available" dialog) and stamps it with the version and date.

## [Unreleased]

## [1.9.0] - 2026-10-21

### Fixed
- **A video clip no longer loops by default.** It plays once, exactly as made; the last picture then holds and the camera eases from the full frame onto the most prominent feature and travels to the second most prominent (features are found on the clip's last frame; once back in a very long part). Looping is now an explicit switch, with a smooth crossfade into the beginning. This applies to HeyGen clips and to videos you drag in. The camera move added in 1.8.0 *over* the clip itself was removed.
- **Video controls are back, and now cover generated clips too:** start/end trim with "Play this part", the repeat switch, and the camera controls ("Automatic" / "I choose the move", "Aim for me") stay available while a clip is in use. Trimming one clip in a back-to-back set closes the gap.
- **Paid clips could be lost or duplicated.** Splitting a picture no longer plays the same clip in both halves; joining pictures keeps both pictures' clips; Undo brings clips and the video cost back; a Short that starts in the middle of a picture plays the clip from the right moment; clip files are cleaned up when pictures are joined or removed.
- **A HeyGen clip is never lost if the app quits while it is being made:** the order is recorded the moment it is placed and collected on the next start.
- Needless preview rebuilds after every cost update are gone (the preview only rebuilds when something you can see changes).
- `release.sh` refuses to publish while a merge conflict is unresolved.

### Added
- **Progress strip at the very top of the window** for every long task, with a bar, elapsed time and Cancel; parallel tasks get a row each. A clip's bar is an estimate (HeyGen reports no progress). A green "Done — … cost $x" line shows afterwards.
- **Make video clips for all pictures** (one price confirmation first, refused if your OpenRouter credit would not cover it), and a cost confirmation before "Make all missing pictures".
- **Add my earlier pictures to the Pictures folder** (Pictures folder menu): copies pictures of songs made before 1.8.0, dated by when each was made.
- The timeline starts hidden on a small screen.
- `AUDIT.md`: what changed in each release since 1.5.4 and why, with the findings of a code sweep.

## [1.8.1] - 2026-10-21

### Changed
- **Each new picture is a new perspective on the same scene.** When a picture is drawn, the previous picture is sent as a reference: the new one keeps the same world (place, people, objects, season, art style) but shows it from a dramatically different camera angle, distance and framing, and shows what its own idea describes. The style guide is sent too when it is a different picture. Cost: about half a cent per reference (a typical picture with both is about 1.9 cents including the focal-point check).
- **Neighbouring picture ideas must look dramatically different.** The idea writer is told to change the subject, kind of shot (wide, low, aerial, detail, framed, silhouette), scale, colours and time of day from one picture to the next; ideas whose kind of shot repeats or whose words are too close to the previous idea are rewritten, and the story check has a fourth test for "too similar to the idea before". More varied viewpoints were added to the random looks.

## [1.8.0] - 2026-10-21

### Added
- **Two focal points in every picture idea, and a camera that travels between them.** New picture ideas name two clearly different things to look at, placed apart in the frame (shown under the idea as "The camera moves from … to …"); the drawn picture is asked to include both. After a picture is drawn, a tiny cloud check (about 0.006 cent) finds where each focal point is, and the automatic Ken Burns moves from the first to the second. For video clips, the prompt asks for the action and camera to travel from the first focal point toward the second (the first one animating as it goes), and the same camera move now runs over the clip and the frame it ends on.
- **A shared Pictures folder.** Every picture — drawn by the app or added by you — is also saved in `Pictures` inside your main Music Videos folder as "2026-10-21 Song title 007.png" (date, song, an ever-increasing number) so you can scroll through them. Each song keeps its own copy as well (a free clone on a Mac disk). *Pictures folder* button on the Pictures screen; the file name under each picture shows it in Finder.

## [1.7.2] - 2026-10-20

### Changed
- **The automatic camera makes one journey and never goes back and forth repeatedly.** It travels from one subject to the next; in a long section (11 s or more) it comes back once at the end. With three or more subjects it goes A → B → C and stops. (Before, long sections ping-ponged.)
- **Your own Ken Burns move is as big as the picture allows.** The view is now zoomed in as far as is sensible (up to 2.4×): *Moves closer* goes from a fairly close view to the closest, *Moves wider* the other way, and *Stays level* is a close, steady view that travels between your two points. A larger zoom always keeps both points inside the picture. The dashed frames shown while you place the dots match.

## [1.7.1] - 2026-10-20

### Changed
- **A new video clip is used straight away.** The moment a clip arrives it is switched on (with *Use this clip* as the default button, so Return accepts it); *Redo* or *Discard* are still there if you don't like it.
- **The automatic camera always moves, from one subject to the next.** The app finds the main subjects of each picture (people first, then other salient objects) and the camera travels from one to the next at a steady, visible pace — zoomed in on each (about 1.75×) — instead of drifting slowly. A picture with one subject moves from a wide view in on the subject. Long sections keep travelling back and forth between the subjects, so a picture is never left standing still. The frame after a video clip does the same: it starts wide (matching the clip) and moves in on the subjects. Pictures with a camera move you set yourself are unchanged.

## [1.7.0] - 2026-10-20

### Added
- **Picture ideas that move the story forward, checked by the AI on your Mac.** New ideas follow on from the previous picture's idea. After the ideas are first written and after every *Another idea*, a local "story check" fixes ideas that are physically impossible, don't follow on from the one before, or don't fit the song, and says what it changed. Ideas you edit yourself are never touched, and clicking a generate button doesn't run it.
- **Style guide picture.** The title card (or any picture you choose with *Use as the style guide*) is sent as a reference with every other picture, so the whole video shares one look. Measured cost: about half a cent per picture.
- **HeyGen video clips.** Ken Burns stays the default. Under each picture: *Make this a video clip* (5–15 s, the section's length), with the price shown first and the clip played back for you to approve, redo or discard; sections over 15 s hold the last frame and carry on with Ken Burns. *Make the whole section as video* chains clips back to back (each starting on the last frame of the one before), pausing after each so you can watch it. A cheap automatic check warns about physically impossible-looking clips (switch off in Settings). Real costs are shown in the green strip; the only limit is your OpenRouter credit.
- **A true-to-scale timeline at the top of the Song and Pictures pages.** Ruler + waveform, lyric lines at their real times, purple music interludes, pictures with thumbnails and **draggable borders** (snapping to lyric lines; Option = no snap; double-click to add, Delete to join), and **draggable Shorts** (move, resize, add, delete).

## [1.6.2] - 2026-10-19

### Fixed
- **All the lyrics are visible again on the Song page timeline.** Every line of the song shows in order under its picture, with its time and a play button; music-only pictures show a purple "♪ Music" block. Clicking a number on the strip scrolls the list to that picture.
- **"Start new picture here" can no longer wipe your other pictures.** A split may only add the one new cut; if it would change anything else it is refused with a message. The new picture's artwork starts as a copy of the picture it was split from, an **Undo** button appears right after the change, and your picture divisions are saved on disk as you make them (they come back after listening again or restarting the app). The confirmation now uses the exact time you chose.

## [1.6.1] - 2026-10-19

- Bug reports now send only the report text you can review and optional technical details; status checks keep the right report when a new report is added during refresh.

- Rebuilt the first-page picture and Shorts timeline with a shared time ruler, readable labels, zoom, playback cursor, and an expandable editor.
- Fixed stale timeline drafts overwriting newer artwork, camera and prompt edits; Undo now tracks later project edits, retains paid artwork and accounting, and cannot run during background tasks.
- Fixed joins at automatic boundaries. Explicit picture splits and joins now work across music and singing, preserve every other boundary, and never alter Shorts or source audio.
- Added independent first-page Shorts creation, suggestions, naming, start/end sliders, splitting and joining. Joining includes intervening audio and explains the three-minute limit. Picture divisions no longer silently create Shorts.
- Added Undo/Redo for timeline, Shorts and artwork edits, explicit reset wording, whole-word placement and split previews. Boundary drags save once when finished; save failures are visible.
- Drag picture rows using macOS drop targets to move or swap artwork, or use the labeled reassignment menu. Splits reuse artwork; joins and replacement keep previous pictures and videos selectable as alternatives.
- Fixed version changes waiting indefinitely for restart when the Versions sheet was still open.
- Added in-app version selection and rollback, persistent stay-on-version and skip/unskip controls, project and media backups, and automatic holding after rollback. Downloads require a checksum and validate the requested version and macOS compatibility.
- Fixed stale preview builds and incomplete preview cache keys; corrected audio synchronization during silent title-card pre-roll and serialized caption updates with frame rendering.
- Isolated song-listening caches, fixed stale copied audio, kept raw lyric formatting during boundary edits, and sanitized nested/unfinished stage directions and older saved captions.
- Hardened the undeployed bug-report relay with bounded request parsing, required rate-limit configuration, and quoted report text.
- Fixed both Shorts editors moving the opposite end at the three-minute limit, and rebuilt restored previews when undoing style changes.
- Hardened short-video trims, section indexing, and saved-artwork file cleanup. Updated the guide to describe the new controls.

## [1.6.0] - 2026-10-18

### Added
- **The song on a timeline (first screen ▸ Divide into parts).** Press *Listen to the song first* (about a minute; no pictures are made, nothing is spent) and the lyrics appear in song order with the time each line is sung, and every music-only break as a purple **♪ Music** block with its time and length. Cut between lines to add pictures; each picture's bar has **Split in two** and **Join with above**; **Split long verses** splits every verse over 30 s into pictures of 20–30 s. *Plan my video* reuses the listening. Once planned, thin bars on the right show which lines each Short covers.
- **Brackets are never shown.** Everything in [ ], { }, < > or ( ) — Suno tags, stage directions, backing vocals — is removed from the lyrics everywhere (captions, Shorts, picture ideas, the timeline). A tag on its own line still marks a new verse.

### Changed
- **One picture per verse and one per music break** is the new default (instead of "a picture every 15 s"). A music break over 40 s is split into equal pictures of up to 30 s; breaks under 4 s join the neighbouring verse; with no verse marks, each run of singing between two music breaks is a verse. The *A picture every N s* stepper is gone.
- Removed the *Add pictures from a folder* button (drag a picture into a part, or use *Make all missing pictures*).

## [1.5.4] - 2026-10-17

### Fixed
- **The start/end markers on the video-clip strip now follow the mouse.** Before, pressing on a marker made it run away to the end; now it moves exactly with the pointer and stops where you let go.
- **Video clips that repeat now loop smoothly.** The end of the clip dissolves into its beginning (up to 0.8 s) and playback carries on from there — no more hard cut back to the start.

## [1.5.3] - 2026-10-17

### Changed
- **Clearer, resizable video-clip controls.** The start/end panel is rebuilt: a large preview with *Play this part*, a taller picture strip with big grab-handles (START time above, END time below so they never overlap), and two cards — *Start of the clip* and *End of the clip* — each with the time in large type, a **Start here / End here** button (click a picture in the strip to choose the moment) and −0.5 / −0.1 / +0.1 / +0.5 s buttons. It re-arranges itself for small and large windows (side-by-side when wide, stacked when narrow).

## [1.5.2] - 2026-10-17

### Changed
- **The automatic camera move is clearly visible now.** The default sweep across the picture is closer in (about 1.45×) and travels roughly half the width of the frame while slowly zooming in, and the diagonal glides are wider too — obvious motion, still smooth.

## [1.5.1] - 2026-10-17

### Added
- **Choose which part of a video clip plays.** Under a video clip's picture box: a strip of pictures from the clip with a green **START** and a red **END** marker. Drag the start later or the end earlier (everything outside is dimmed); small −0.5/−0.1/+0.1/+0.5 buttons for fine tuning; the picture beside it shows the frame at the marker you moved; *Play this part* shows the chosen stretch; *Use the whole clip* resets. The default is still the whole clip. Used in the video, Shorts and the preview.

## [1.5.0] - 2026-10-17

### Added
- **Report a problem — and see whether it is fixed.** *Help ▸ Report a Problem…* (also a button in the Help window and on error messages). Anyone can send a report without an account; it arrives as an issue in the project's GitHub list. **My reports** shows *Received / Being worked on / Done ✓* plus the author's reply, and the app tells you at start-up when something you reported is fixed. Only the text you type and the app/macOS/Mac type are sent. The tiny relay that files the reports is in `relay/` (setup in `relay/README.md`); until its address is set in `scripts/release.conf`, the sheet offers *Copy my report* / *Open the bug page*.
- **Video clips instead of pictures.** Drag an MP4 or MOV into any part's picture box (or click and choose it). It plays while the part is on screen and repeats if shorter; works in the full video, Shorts and the preview. Clips are copied into the song's folder.

### Changed
- **Picture ideas are always bright.** The AI is told every picture must be bright, colourful and well lit (never dark, gloomy or night-time), the random time-of-day/weather choices no longer include night, fog or gloom, and every picture request ends with a brightness reminder.
- **Faster, more dynamic automatic camera.** The default move is now a quick sweep across the whole picture, edge to edge, ending on the subject, alternating direction from picture to picture (about one in five is a diagonal glide).

## [1.4.2] - 2026-10-17

### Fixed
- **The picture on the Pictures screen is widescreen (16:9) again** instead of a square, and it now grows and shrinks with the window (up to a much larger size).
- **The full-video Preview stays widescreen** after you have visited the Shorts tab.
- **Shorts: all the caption settings are always visible** — Title, Words (Pill, Pop, Big, Sweep, Surprise) and Colour (Hot pink, Sun yellow …) — and choosing one switches the clip to the lively style so the pink pill etc. always shows.
- **Better window resizing**: the picture list can be wider, and the first screen's left column adapts instead of keeping a fixed width.
## [1.4.1] - 2026-10-17

## [1.4.0] - 2026-10-17

### Changed
- **The Shorts page is now one screen with no scrolling** (designed in Claude Design, option A). Clips are **tabs along the top**. On the left: name + length pill, the whole-song map, a **Where it starts / Where it ends** switch with ONE large close-up under it (waveform, words, beats, purple music-only stretches), the nudge buttons and *How it finishes* for the end, and the play buttons (*Play the Short, Repeat, Browse the words, Make it ~30 s*, and *Sticks to*). On the right: the vertical preview, caption timing, the look (Lively/Simple, title, words, colour dots) and **Make this clip**. *Browse the words* opens the word-by-word timeline for finding a part (click to hear from there, then start/end the Short there).

### Changed
- **Shorts page rebuilt around two things: finding the part, and dialling in each end.** *Where it starts* and *Where it ends* each show a close-up of that end — waveform, the words, the beats (blue ticks) and the **music-only stretches tinted purple ("♪ music only")**. **Click or drag anywhere on the close-up and that end goes there**, and you hear it at once. The text says when the last word ends and how many seconds of music-only follow, so you can stop exactly where you want in an instrumental ending. Nudge buttons are plain: *◀ beat, −1 s, −0.25 s, −0.05 s, +0.05 s, +0.25 s, +1 s, beat ▶* (every press plays the result), plus *Hear the ending*.
- **Snapping you can see and choose.** *Markers stick to: Smart / Beats / Words / Off.* Smart sticks to word edges while words are sung and to the **nearest beat in music-only parts** (so an instrumental ending is no longer pulled back to the last word); Shift still turns it off. The coarse whole-song map no longer snaps while you drag (a few pixels there are seconds) and settles on a word or beat when you let go.
- **How it finishes**: *Quick fade, Slow fade (2 s), Stop sharply, Loop back to the start* — new fade options apply to both the picture and the music.
- Clearer buttons: *Play the Short, Play again and again, Start/End the Short here* (a card where you click on the word timeline, which also plays from that spot), *Hear the ending*.

### Changed
- **A new way to choose a Short: one timeline.** The song is shown whole, with its parts (the pictures) as coloured blocks on top and the waveform below. The **bright box is your Short, everything else is dimmed**: drag the box to move it, drag its edges to change the start and end. Edges **snap to the nearest word or line edge** within ~8 pixels (hold **Shift** for free movement), press a part block to select all of it, and a close-up strip below shows each word. Under it, the lyrics are listed **by part**: click a line to choose it, **press and drag across several lines** (the box follows), Shift-click to stretch, *Use this whole part*, *Make it about 30 seconds*.
- **See the words on the timeline.** A new **The words** strip under the waveform shows every word of the song in large type at the moment it is sung (scroll sideways; the words in your Short are highlighted between a green start line and a red end line). **Click a word to start the Short there, Shift-click to end it there.** The close-up waveform also writes the words on it when zoomed to 20 s or less.
- **Length guardrails.** A pill on the box shows the length (*29.9 s / 60 s*) and the box is outlined **orange under 5 s (too short), green 15–60 s (ideal), red over 60 s** with a message (a Short is still limited to 3:00).
- **Loop preview.** *Loop preview* (or **L** / **Space**) plays just the selection on repeat, starting 0.5 s early. The vertical preview shows YouTube's **safe zones** by default.
- Every Short now also gets a `.json` range file beside it: `clip_id`, `title`, `start_time`, `end_time`, `duration` and the exact times of the words in it.

### Added
- **Help on every screen, with an assistant that answers from the guide.** A **Help** button sits on every screen (and Help ▸ *Help & Questions…*). *Ask a question* answers in plain words using the built-in **guide** (21 sections covering every feature, including a list of what the app cannot do) **and what is on your screen right now** (which screen, what is missing, why a button is grey, costs, models, errors…). It is told to use only that information: if the app can't do something it says *"That isn't possible in this app"*, and if the guide doesn't cover it it says *"I don't know"* instead of guessing; button names it quotes are checked against the guide and a warning is added for names it can't find. *Read the guide* shows the whole guide with search. Tested on 28 sample questions (how-to, impossible, unrelated, screen-dependent).
- **More picture styles you can edit and add to.** 42 ready-made styles (28 new: Pencil Sketch, Impressionist, Film Noir, Pixel Art, Linocut, Sumi-e Ink Wash, Renaissance Fresco, …). *Picture styles* (first screen: *Look of the pictures*; Pictures screen: *Art style*) lets you press a style to use it, **edit any style's name or words permanently**, **add new styles with your own names**, delete styles, put one back to its original, and restore deleted ones. Saved in `styles.json` next to the settings.
- **"Suggest 10 ideas for me" for the setting/scene.** On the first screen (next to the setting field) and in *Setting & description*: the local AI reads the lyrics and offers 10 clearly different places/eras/moods; press one to use it, *Suggest 10 more* for more. `mvideo ideas lyrics.txt` does it from the command line.

## [1.3.1] - 2026-10-16

### Added
- **Picture costs always on screen.** A green strip across the top of every screen shows what you have spent on picture generation for this song (and how many pictures), **what drawing all the blank pictures would cost** (about the usual price per picture × the blank ones; it updates as pictures are added or made), what you have spent across **all your songs**, and your OpenRouter credit left (turns orange when it wouldn't cover the blank pictures). Each figure has a tooltip.

### Changed
- **Your verse marks cut the lyrics by default.** If you don't make any cuts yourself, the pictures and Shorts are now cut exactly at the verse breaks you typed (blank lines and tags like *[Chorus]*): one picture per verse. The *Divide into parts* screen shows those cuts, and your first click turns them into cuts you can change. Lyrics with no blank lines at all are still divided by the app, and so are lyrics where the breaks would make absurdly short pictures (shorter than ~6 s each). Going back to the Song screen shows your lyrics with the same blank lines.

## [1.3.0] - 2026-10-16

### Added
- **Setting and theme for every picture.** A new field on the first screen (and in *Setting & description* on the Pictures screen), e.g. *Brightly lit colonial Philadelphia*. The AI is told every picture must take place there (translating anything in the lyrics that doesn't belong into something that does), the description is written with it, and the setting is **stated explicitly at the front of every picture idea** and in the copied/generated prompt. `mvideo plan --setting "…"` does the same from the command line.
- **Randomness in every prompt, never the same twice.** Each section is dealt its own *look*: a time of day, a kind of weather and a camera view, drawn without repeats from shuffled lists, so neighbouring pictures never share them. The similarity check ignores the shared setting words, so prompts that are alike apart from the setting are still caught and rewritten. *Another idea* draws a fresh random look every time. In a test with a fixed setting, 17 prompts had no duplicates (most similar pair 19 % overlap).

### Added
- **Choose the camera move yourself (Ken Burns).** Under each picture: *Camera ▸ Automatic* (as before) or *I choose the move*. Then two numbered dots appear on the picture: drag **① green = where the camera starts** and **② red = where it ends**; dashed frames show exactly what the viewer sees first and last, and the picture glides between them. *Moves closer / Stays level / Moves wider* sets the zoom while it travels, *Swap start and end* reverses the direction. Used for the full video and for Shorts, and shown in the live preview.

### Changed
- **Dividing the lyrics is now a "cut the lyrics" screen**: coloured picture bars (“Picture 2 · 3 lines”), a clear “✂ cut here” line between every two lyric lines, click a bar to join pictures, plus *One picture per verse*, *N equal pictures* and *Start over*.
- **Pictures screen**: the “Song description and art style” drop-down is gone. The top area is a message plus plain buttons (*Make all missing pictures, Add pictures from a folder, Song description, Art style, Picture maker key & credit, Copy all picture ideas*); description and art style open in their own windows, and art styles are buttons you press. The bottom bar is just *Preview*, a small *1080p + clips* options button and **Make my video**, so nothing can cover anything else.

## [1.2.2] - 2026-10-16

### Added
- **Divide your lyrics into parts.** On the first screen, *Lyrics ▸ Divide into parts* shows your lines with a scissors button between them: click to start a new part, click again to join. **Each part becomes exactly one picture**, and Shorts are built from whole parts (grouped to about 30 s; a part much longer than a Short is split at its pauses) so a Short never starts or ends in the middle of a part. *Use my verse breaks* turns your blank-line verses into parts as a starting point; *Clear my parts* returns to automatic. In the text a part break is a line containing `---`. With no `---` lines the app divides the song itself as before. Parts are remembered in the project.
- **Go back to any step.** The **Song · Pictures · Video** steps at the top are buttons: from the finished video you can return to Pictures or to Song (title, lyrics and song are kept), and from Pictures back to Song or forward to Video once one exists. Nothing is lost by going back.
- **A song with a different name starts a new project.** Choose or drop an MP3 whose name differs from the one you are working on and the app starts a fresh video (the earlier one stays saved; *Open earlier project* brings it back). A file with the same name keeps the project; while you are only drafting, the title follows the file name until you type your own. If you change a song's title, lyrics or file, the main button says **Plan as a new video**, otherwise **Back to my pictures**.

### Fixed
- **Small screens (MacBook Air).** The progress bar for background tasks is now a strip above the screen instead of a panel floating over the buttons; the first screen's left column scrolls and its bottom bar shrinks to icons (then two rows) instead of overlapping; the Pictures screen's top area is limited to ~40 % of the window height and scrolls, and its top and bottom bars adapt; Shorts controls wrap; the window keeps itself inside the screen and can be as small as 860 × 560; dialogs scroll instead of running off screen.

## [1.2.1] - 2026-10-16

### Fixed
- **Gemma (language model) failing with “key … not found”** on a second Mac. Downloads never checked the server's reply, so a busy or blocking Hugging Face could hand back an error page that was saved as the model file. Downloads now check the server status, verify big files against Hugging Face's checksums (re-downloading a damaged one once), record what was downloaded, and an install whose files are missing, the wrong size or obviously not model weights is treated as *not installed* so the app offers the download again instead of failing during planning.

### Added
- **On-device models in Settings and on the setup screen.** *Parakeet Ultra* and the language model (e.g. *Gemma 4 E2B*) each show whether they are downloaded and how big they are, a live percentage while downloading, and Download / **Download again** buttons. A size picker (Small / Balanced / Best) chooses which language model is fetched.

### Changed
- **Shorts are saved next to the main video**, not in a `Shorts` subfolder (your chosen output folder, or the folder beside the project). Files are named `<Song title> – <clip name>.mp4` so several songs can share one folder. Shorts you already made stay where they are.

### Added
- **The music before the first words now gets its own picture and prompt.** When the first words start 3 s or more after the title card, the song gets a *Music before the words* section (shown after the title card until the first lyric), with a prompt that sets up the song's world. Music-only breaks and the outro are described in context too (the words before and after them), instead of one generic "establishing scene". Older projects get an **Add picture for the opening music** button on the Pictures screen (CLI: `mvideo add-intro <project>`); existing pictures stay put.
- **Every section's prompt is unique.** After writing, near-duplicate prompts (word overlap ≥ 35 %) are rewritten with the other prompts listed as "must differ from"; as a last resort a different time of day or viewpoint is added. "Another idea" also avoids all existing prompts, and a model echoing the style line at the start of a prompt is cleaned up.

## [1.2.0] - 2026-10-16

### Fixed
- **"Record it as it plays" stopped working after an update** even though *Screen & System Audio Recording* was switched on. macOS remembers that permission by the app's signature, and every build had a different ad-hoc signature, so each update invalidated it while System Settings still showed the old entry as ON. Builds are now signed with a fixed designated requirement (the bundle identifier), so the permission survives future updates. When macOS still refuses, a **Let's fix recording** window repairs it in three clicks (clears the stale entry, asks again, restarts the app); it is also under Settings ▸ *Fix recording permission…*. Updating to this version needs the permission granted once more.

### Added
- **In-app updates, made obvious.** A blue **“Update available — version X”** strip appears across the top of the window with *What's new*, **Update now** and *Later*. *Update now* downloads the new version, checks its SHA-256, installs it and restarts the app by itself, showing a progress bar and the current step. The Help and app menus have **Check for Updates…** (it becomes *Update to Version X…* when one is waiting), and Settings has an **Updates** section with the current version, status, last-checked time and a *Check for updates* button.

## [1.1.0] - 2026-10-16

### Fixed
- **Captions slightly off pace with the singing.** Every caption now follows a per-song timing offset that defaults to 0.06 s early (audiences read late captions as lagging), and the Shorts word pill now starts moving *before* each word so it lands on the onset instead of 0.1 s after it. New **Show sooner / Show later** buttons under the preview shift every caption of a song in 0.05 s steps; the setting is saved with the project (`captionShift`).
- Lyric timing for words the speech model missed now stays inside their own line instead of stretching across pauses; sung words hold for a natural length (from the other AI's alignment work, with its extra −30 ms offset removed so the caption offset is the single timing control).

### Changed
- **Much easier to use.** Every screen was reworded in plain language and every button, field and picker has a tooltip that explains what it does. A **Step bar** (Song → Pictures → Video) shows where you are, a green **next step** card says what to do next, and Help ▸ **Quick Guide** (also the `?` button, and shown on first launch) walks through the whole process.
- Pictures screen simplified: one "Picture maker" card (make all missing pictures, credit left), the song description and art style are tucked into a section that is closed by default, line-timing buttons are larger, and technical wording ("Reroll", model names) is gone from the main screens.
- Shorts editor reworded ("Cut my song into clips for me", "Choose the lines myself", "Try a different look", "Move to the nearest pause") with tooltips on every control.
- Settings reorganised: Where things are saved · Picture maker · Shortcuts & help.

### Added
- `scripts/bench/lag_scan.py` (checks a constant caption offset against acoustic onsets) and a hidden screenshot mode (`MV_SNAPSHOT_DIR`) for layout checks.

## [1.0.5] - 2026-10-16

### Added
- **OpenRouter image generation (`openai/gpt-image-2.5-sunburst` 16:9 Medium):** Enter your OpenRouter API key (in Settings or directly from the Plan screen) to generate individual section pictures, reroll any picture, generate all missing pictures, or reroll all pictures for the entire song (`--generate-images` in the CLI).
- **Live OpenRouter credit balance, cost estimates & persistent per-song total cost:** Displays your remaining OpenRouter credits alongside the estimated cost per image (`~$0.048`) and bulk generation cost, and persistently tracks and saves the cumulative USD spent on each song (`totalGenerationCostUSD` and `imagesGeneratedCount`) inside `project.mvproj`.

### Fixed
- **Silky-smooth, non-jumping Ken Burns camera engine:** Re-engineered `PhotoScene` with aspect-aware valid crop domain clamping, logarithmic (exponential) zoom interpolation (`z0 * (z1 / z0)^u`), perspective-coupled pan interpolation (`alpha = (1/z0 - 1/z(u)) / (1/z0 - 1/z1)`), and duration-scaled cosine S-curve easing so the camera never collides with image borders mid-shot, never stalls or whips across the middle, and never reverses zoom direction or jumps within a picture. Also smoothed beat-pulse envelopes (`0.045s` raised-cosine attack + exponential decay) and added cross-dissolve transitions.
- **Setup screen "Record Song Playing" layout stability:** Fixed the recording zone and live waveform meter so switching to **Record Song Playing** or actively recording a song never expands the left column vertically or horizontally.

## [1.0.4] - 2026-10-16

### Added
- **Live song recording, real-time transcription & automatic silence trimming:** Record any song playing on your Mac (via `ScreenCaptureKit` system audio) or from a microphone/audio input, watch Parakeet transcribe the lyrics in real time as it plays, and automatically trim leading and trailing silence when you stop. Includes one-click **Paste Over Lyrics**, **Auto-Transcribe**, and **Trim Silence** actions.
- **Automated 4–7 ~30-second Shorts when making the main video:** Every planned song now automatically partitions into 4–7 ~30-second Shorts cut at natural stanza breaks and vocal pauses (`Pipeline.autoShorts`). Leave **Also make Shorts (~30s)** checked when clicking **Render Video + Shorts** (or pass `--with-shorts` on the CLI) to render the main widescreen video and all 4–7 Shorts with AI-written opening hooks in a single pass. Also added **Auto-Make 4–7 Shorts (30 s)** and **Render All Shorts** buttons in the Shorts tab.
- **Curated visual style preset dropdowns:** Pick from 14 built-in art styles on the Setup and Plan screens (**Oil Painting**, **Acrylic Painting**, **Vector Image**, **Realistic**, **Watercolor & Ink**, **Studio Anime**, **Vintage Comic Book**, **Neon Cyberpunk**, **Charcoal & Gold Leaf**, **3D Claymation Diorama**, **Ukiyo-e Woodblock Print**, **Stained Glass**, **Retro 1970s Poster**, or **AI Auto**).
- **Clear on-screen progress bars & task cancellation everywhere:** Floating progress bar banner with percentage, elapsed clock, phase description, and **Cancel** button whenever any background task runs (rewriting song description, regenerating prompts, loading a folder of pictures, re-syncing lyrics, writing Short hooks, live preview preparation, and audio transcription/silence trimming), plus **Cancel** buttons on full video and Short renders that cleanly remove partial files.
- **Interactive Focal Point & 9:16 Short crop preview:** Drag the orange focal-point target directly on any loaded picture in the Plan screen to aim the Ken Burns camera pan and preview the dashed 9:16 vertical Short crop box, with an **Auto Focus** reset button.
- **Per-line lyric timing nudges & audition:** Play (`▶`) individual lyric lines in any section and nudge their timing (`−0.5s`, `−0.1s`, `+0.1s`, `+0.5s`) without re-running full alignment.

### Changed
- **Faster rendering & lower CPU overhead:** Replaced the `AVAssetWriter` polling spin-wait with an event-driven pending frame queue, cached the `t = 0` opening frame for looping Shorts, and deduplicated `TextBitmap` rasterization across repeated words in Shorts.
- **Single-pass audio decode & persistent waveform/beat caches:** 16 kHz mono PCM is decoded once in memory and `waveform.json` and `beats.json` are saved inside the `.mvproj` project folder for instant project reopening and Short scrubbing.
- **Beat-synced sub-shot cuts & vertical subject framing:** Dynamic Short sub-shots now snap cut times to detected musical beats and anchor horizontal pans to the detected vertical subject focal point (`focus.y`).

### Fixed
- **Karaoke word highlight drift:** Fixed substring matching on repeated short words within the same lyric line (`LyricLayer.buildRows`) by advancing past whitespace and matching anchored tokens first.
- **Resilient local AI prompt parsing:** Added a regex salvage parser and per-section fallback in `PromptWriter` so truncated or malformed LLM JSON output never aborts a video plan.
- **Project disk cleanup:** Replacing or removing a section's picture now automatically deletes unreferenced `full/section_*` and `thumbs/section_*` files from the project folder.

## [1.0.3] - 2026-10-16

## [1.0.2] - 2026-10-16

## [1.0.1] - 2026-10-16

### Changed
- Balanced tier now uses Gemma 4 E2B (faster, closer to the song's era than Qwen3-4B).
- Clear progress panel: percentage, bar, current task, step checklist, elapsed and time left (planning, rendering, setup, Shorts).
- One "Saving to…" button on the main screen sets the folder for all projects, pictures and videos.

### Changed (privacy)
- Releases are public; installer and in-app updater download anonymously (no GitHub account needed).
- App identifier is now com.drawsomerex.musicvideomaker; commit author is the GitHub handle only.
- Removed song-specific test scoring script and example text.

### Added
- Settings → Dock: add/remove the app from the Dock.

### Added
- Model benchmarks (`docs/model-benchmarks.md`, `scripts/bench/`) and hidden `mvideo align-check`; confirmed default model tiers.

## [1.0.0] - 2026-10-16
First release.

### Added
- **Two-step workflow:** plan (sync lyrics, split the song into sections, write a shared style + one image prompt per section), then load your own pictures and render. Projects are self-contained folders (`project.mvproj`, `audio.mp3`, `transcript.txt`, `lyrics_synced.txt`, `prompts.md`, pictures) that can be reopened and edited.
- **Exact lyric timing** from Parakeet Ultra word timestamps (4-minute song in under 3 s), aligned to your pasted lyrics; the on-screen text is always yours.
- **Rendering:** Ken Burns camera, feathered wipes/iris/blinds/push transitions, karaoke lyrics, title card, hardware H.264 at YouTube-friendly bitrate; memory-lean and thermal-aware for 16 GB fanless Macs.
- **YouTube Shorts (1080×1920):** pick lyric lines (click / shift-click / In / Out), waveform with zoom-to-scrub and audition, live preview with draggable captions and safe zones, hard 3:00 limit, whole-song mode that splits into parts under 3:00, dynamic style kit (title opening, pink word pill, calm motion, loop ending, optional closing text), 3-variant A/B renders, AI-written upload text.
- **Local AI:** works through oMLX (hidden headless engine, never touching your oMLX settings) **or** fully standalone with Swift MLX (`install_native.sh`: Parakeet Ultra 4-bit 0.46 GB + a Qwen model, tiers small / balanced / best).
- **Distribution:** `release.sh` publishes to GitHub Releases; `install.sh` installs on a new Mac; the app updates itself (checksum-verified).
- Folder choices for projects and finished videos; app icon; command-line tool `mvideo`.
