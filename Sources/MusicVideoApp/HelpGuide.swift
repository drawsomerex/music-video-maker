// The built-in help guide. It is shown in Help ▸ Read the guide AND it is the only source the "Ask a question" assistant may answer from,
// so every statement here must be true of the app. When a feature changes, change this text too.
import Foundation

struct HelpSection: Identifiable {
    let id: String
    let title: String
    let keywords: String          // extra words people might use when asking (synonyms)
    let body: String
}

enum HelpGuide {
    static let sections: [HelpSection] = [
        HelpSection(id: "overview", title: "What the app does", keywords: "start begin overview about how works make video steps process three", body: """
        Music Video Maker turns a song and its lyrics into a finished music video (an MP4 file) and YouTube Shorts (short vertical videos).
        There are three steps, shown at the top of the window as Song, Pictures and Video:
        1. Song: choose your song file, type its title and paste your lyrics, then press "Plan my video". The app listens to the song, matches each lyric to the moment it is sung, divides the song into parts, and writes a picture idea for every part.
        2. Pictures: every part needs a picture. You can drag in your own pictures, or let the app draw them (this needs an OpenRouter key and costs a few cents per picture). You can preview the video.
        3. Video: press "Make my video". The finished video is saved on your Mac.
        Everything the app does with your song (listening, matching lyrics, writing picture ideas) happens on your Mac. Only the optional picture maker uses the internet.
        You can click the Song, Pictures or Video step at the top at any time to go back or forward. Nothing is lost.
        """),
        HelpSection(id: "song", title: "Song screen: choosing the song and typing the details", keywords: "mp3 wav file drag drop choose load title subtitle lyrics paste record microphone audio song first screen", body: """
        On the first screen (Song):
        - Your song: drag an MP3 or WAV file onto the box, or click the box to choose one. M4A, AIFF and FLAC files also work.
        - "Record it as it plays": instead of a file, the app can record a song that is playing on your Mac (choose "System audio") or from a microphone or audio input. Press "Start recording", play the song, press "Stop recording". Silence at the start and end is cut off automatically, and the lyrics can be written as it plays. The first time, macOS asks for permission.
        - Song title: shown on the opening title card and used to name the folder where everything is saved.
        - Subtitle on the title card (optional): a short line under the title.
        - Setting and theme for every picture (optional): see the section "Setting and theme".
        - Look of the pictures: press the button to choose a picture style. See "Picture styles".
        - Lyrics: paste or type them on the right. The words on screen in the video are exactly the words you put here. The app only listens to the song to find the timing. A blank line between verses and tags like [Chorus] mark verse breaks (anything in [ ], { }, < > or ( ) is never shown on screen).
        - "Paste from clipboard" replaces the lyrics with whatever you last copied.
        - "More tools" (when a song is loaded): "Listen to the song and write the lyrics for me" and "Cut the silence at the start and end".
        - "Saving to": the folder where all your songs, pictures and videos are saved (default Movies/Music Videos). Press it to choose another folder.
        - "Open earlier project": go back to a video you made before.
        - "Plan my video" is turned off until you have chosen a song, typed a title and added lyrics. Pressing Command and Return also presses it.
        """),
        HelpSection(id: "parts", title: "Dividing the song into parts (pictures)", keywords: "divide cut split verses parts sections scissors lyrics pictures how many pictures verse chorus music break instrumental timeline listen subdivide join dividers", body: """
        On the first Song page, select "Pictures & Shorts". Press "Listen and show the timeline" to find word timings once. No pictures are generated. Planning afterwards reuses this listening. Change the audio or lyrics and listen again for fresh timing.
        The time ruler is shared by the picture and Shorts lanes. Picture widths represent their actual durations. Picture numbers match the Pictures page; the title card is separate. Music-only sections are marked with a music note. The listening point shows where a split will go. Clicking selects or listens; it does not move a Short.
        Use "Expand timeline" for more room, or the timeline zoom buttons for precision. "Listen here" plays from the chosen point and "Stop" stops playback. Moving the listening-point slider edits nothing.
        To join two music sections: first go to the Song page, open "Pictures & Shorts", and select its "Pictures" tab. Find the second of the two sections and press its "Join with previous" button, then confirm "Join pictures". Do not select two rows.
        Pictures tab inside the Song page timeline:
        - "Split picture at point" starts a new picture at the chosen time, after showing the exact time. "Hear this change" plays around that point; use the split button again to commit after listening.
        - Every lyric line of the song is always visible in the list, with its time and a play button, grouped under its picture. Between two lines there is a "start a new picture here (time)" line: click it, then press "Start new picture at (time)". Only that one picture is divided; every other picture stays exactly as it was, and the new bottom picture starts with the same artwork. A bar below the list says what changed and has an "Undo" button.
        - Your picture divisions are saved as you make them, so they are still there if you listen to the song again or restart the app.
        - "Split in two" makes two equal picture sections. Both initially reuse the same artwork.
        - "Join with previous" removes only that boundary. Any neighbors can join, including music-only sections and singing. The first artwork is used and the other artwork is kept under "Choose saved artwork".
        - "Split long sections" divides sections over 30 seconds evenly.
        - "Restore automatic divisions" restores verse and music divisions after confirmation, while keeping artwork and Shorts. It can be undone.
        Automatic divisions start with one picture per verse and music break of at least 4 seconds. Music breaks over 40 seconds divide into pictures of at most 30 seconds. Manual boundaries take precedence, even if all boundaries have been removed.
        Splitting or joining pictures never changes audio, lyrics, or Shorts. Your raw lyrics are kept, including verse formatting. Bracketed stage directions are omitted from captions and picture ideas.
        To split a Short: on the Song page, open "Pictures & Shorts" and select its "Shorts" tab. Choose the Short, move the listening point inside it (at least half a second from either end), then press "Split at point".
        Shorts tab (also on the first page):
        - "Add a Short" adds a 30-second Short at the listening point. "Suggest Shorts" adds suggestions based on lyric pauses. Shorts are created only on request and picture edits never create or rearrange them.
        - Rename a Short, use its Start and End sliders, or press "Play Short". "Keep whole words when placing cuts" places starts before a word and ends after it; turn it off for exact placement.
        - "Split at point" replaces one Short with two independently editable Shorts meeting at that point. Choose a point at least half a second inside the Short.
        - "Join with next Short" includes every moment between the first start and the last end. It is unavailable if the result exceeds 3 minutes; the tooltip explains why.
        - "Delete Short" removes only that Short.
        "Undo" and "Redo" reverse timeline, Short and artwork edits. Command-Z undoes a timeline edit when a text editor does not have focus. A completed drag is one edit and saves once. "Not saved — try again" means you must retry saving before closing.
        """),
        HelpSection(id: "setting", title: "Setting and theme for every picture", keywords: "setting theme scene place era location mood suggest ideas colonial consistent same look", body: """
        The "Setting and theme" field (first screen, and Setting & description on the Pictures screen) is one phrase such as "Brightly lit colonial Philadelphia". Every picture idea is written to take place there, and the setting is written out in full at the front of every picture idea, so it is also in the prompts you copy or send to the picture maker.
        The pictures still differ from each other: every part gets its own time of day, weather and camera view.
        If the lyrics mention something that does not belong in that setting, the AI is told to show the closest thing that does belong there. Small local AI models follow this only partly, so check your picture ideas.
        "Suggest 10 ideas for me" reads your lyrics and offers 10 different settings; press one to use it. "Suggest 10 more" gives more. Nothing changes until you press an idea.
        On the Pictures screen, changing the setting does not change the existing picture ideas until you press "Make new picture ideas" in the Setting & description window.
        Leave the field empty to let the app decide the setting from your lyrics.
        """),
        HelpSection(id: "styles", title: "Picture styles", keywords: "style art look oil painting watercolor anime preset custom edit new delete reset my own", body: """
        A picture style is a few words describing the look of all the pictures (for example oil painting, watercolor or anime). It is added to every picture idea so the pictures match.
        On the first screen press the "Look of the pictures" button; on the Pictures screen press "Art style". The window shows more than 40 ready-made styles. Press one to use it.
        "AI Auto" lets the app write a style that fits your song.
        To change a style: press it, edit the name or the words under "Edit this style", and press "Save changes".
        To make your own style: press "New style", type a name, describe the look in words (the medium, colours, light and mood), and press "Save changes". Your style appears in the list with a star and can be chosen like any other.
        You can change any style: press it, edit the name or the words under "Edit this style", and press "Save changes". Changes are kept permanently for next time. "Back to original" restores a ready-made style. A small pencil marks styles you changed.
        "New style" makes a style of your own (marked with a star). "Delete" removes a style; deleted ready-made styles can be brought back with "Restore deleted styles".
        On the Pictures screen the box "Words used for this song" shows the style words this song uses right now. New pictures use them; pictures you already made are not changed.
        """),
        HelpSection(id: "planning", title: "What happens when you press Plan my video", keywords: "plan planning analyze listening sync time how long wait progress transcribe", body: """
        The app listens to your song (Parakeet Ultra, on your Mac), finds the exact moment each word is sung, matches your lyrics to those words, divides the song into parts, reads the lyrics to write a short description of the song, and writes one picture idea for every part. It takes a minute or two for a normal song. The screen shows a percentage, the current step and the time left. You can press Cancel.
        If the lyrics match the audio badly (under 50 percent of the words), a warning appears. Check that the lyrics are what is really sung.
        When planning finishes, the Pictures screen opens and everything is saved automatically in the song's folder.
        The first screen's main button changes if you come back to it from an existing video: "Back to my pictures" if nothing was changed, or "Plan as a new video" if you changed the song, title, setting or lyrics (the earlier video stays saved).
        """),
        HelpSection(id: "pictures", title: "Pictures screen: the parts and their pictures", keywords: "pictures screen sidebar list parts title card instrumental music before words picture idea prompt another idea copy drag drop replace remove", body: """
        The list on the left shows the title card and every part of the song with its picture (a plus sign means no picture yet). Click a part to work on it.
        For the selected part you see:
        - "Words in this part": the lyric lines. The play button plays that line. The small −0.5s, −0.1s, +0.1s and +0.5s buttons move just that line earlier or later in the video.
        - "Picture idea": a description of the picture. You can edit it. "Another idea" asks the AI for a different one (it avoids the ideas already used). "Copy" copies the idea together with the style and setting so you can use it in another image maker.
        - Drag a picture row onto another section in the sidebar. "Move here" means the target is empty; "Swap pictures" means both sections exchange their selected artwork. "Use in another section…" provides the same choices without dragging. Undo reverses either action.
        - "Earlier versions" (under the picture, when a part has had more than one): small thumbnails of every picture this part has had — each "Try another picture", your own files, and artwork kept after a join. The one in use is outlined. Click a thumbnail to use it again (free); the ✕ throws a version away (a copy stays in your Pictures folder, and Undo brings it back). Rest the pointer on one to see when it was made and what it cost.
        - While the app is drawing pictures or writing an idea, everything stays usable: you can click other parts, edit their ideas, trim clips and move the camera. Only the picture being worked on right now is locked (a small note says so). Splitting, joining or moving pictures waits until it is done.
        - "Picture for this part": drag a picture or a video clip (MP4 or MOV) into the box or click it to choose a file. Use widescreen pictures (16:9), 1920 by 1080 pixels or larger. Other shapes are cropped to fit and the app warns you.
        - "Make this picture for me" draws the picture with the picture maker (needs an OpenRouter key, costs a few cents). "Try another picture" draws a new one. "Choose a different file" and "Remove picture" are under the box.
        - "Camera": see the section "Camera movement".
        Parts that are only music have names like "Music before the words", "Music break" and "Music after the words" and get their own picture idea.
        The first item, "Title card", is the opening picture behind the song title.
        The bar above the pictures has one row: "Make all missing pictures", "Make video clips for all pictures" and "More" (Setting & description, Art style, Picture maker key & credit, Make Shorts automatically, Copy all picture ideas), with one line saying what to do next when there is room.
        Smaller windows: the timeline folds into a slim strip of coloured blocks (one per picture, pale when it has no picture yet; the pink line under them shows the Shorts) so the pictures keep the room. Click the strip or "Timeline" to open it; the app remembers your choice. In a tall or full-screen window the full timeline shows, the picture grows with the window, and in a wide window the words and the idea sit beside the picture.
        "Show folder" opens the song's folder in Finder. "Close" closes the song (it stays saved).
        """),
        HelpSection(id: "descriptionsheet", title: "Setting and description window", keywords: "description song about write again new picture ideas regenerate all prompts", body: """
        On the Pictures screen, "Setting & description" opens a window with the setting field, "Suggest 10 ideas for me", and the description of what the song is about (written by the app from your lyrics; you can edit it).
        "Write it again" has the AI read the lyrics again and write a new description and new picture ideas. Your edits to the description are replaced.
        "Make new picture ideas" keeps the description and setting as they are now and writes fresh picture ideas for every part. Pictures you already made are kept, but their ideas change.
        """),
        HelpSection(id: "pictureMaker", title: "Picture maker (OpenRouter), keys and costs", keywords: "openrouter key api credit money cost price pay generate draw ai images make pictures free paid spend balance", body: """
        The picture maker draws pictures from your picture ideas through the OpenRouter service. It needs an internet connection, your own OpenRouter key and credit on that account. It is not free: each picture costs a few cents (about 5 cents is typical; the app shows the real price it was charged).
        Add your key with "Picture maker key & credit" (Pictures screen) or in Settings under "Picture maker (optional)". The key is saved in a private file on your Mac and is only sent to OpenRouter.
        You do not need the picture maker. You can make pictures anywhere else and drag them in.
        A green strip at the top of every screen always shows: what you have spent on this song (and how many pictures), what drawing all the blank pictures would cost (an estimate), what you have spent on all songs together, and your OpenRouter credit left (it turns orange when it would not cover the blank pictures).
        "Make all missing pictures" draws a picture for every part without one and asks no further questions; it shows progress and can be cancelled. "Make every picture again" (inside "Picture maker key & credit") replaces all pictures after you confirm.
        """),
        HelpSection(id: "camera", title: "Camera movement (Ken Burns effect)", keywords: "camera ken burns zoom pan move direction start end dots closer wider level focus motion drift", body: """
        Every picture moves while it is on screen. Under each picture, "Camera" has two choices:
        - "Automatic": one steady, cinematic move per picture: from the first focal point to the second while closing in a little (or a push-in on a single subject). It goes one way only (never up, then down, then across), at the same calm speed in every picture (about 8% of the screen width per second across and about 4.5% per second closer), with only a very short ease at each end. A short picture travels less far; a long one travels as far as the picture allows, a little slower, and never back. You can drag the orange dot to aim it, or press "Aim for me" to let the app find the spot. "Show the aim" shows the dot and the dashed box that is kept in the tall YouTube Shorts version.
        - "I choose the move": two numbered dots appear on the picture. Drag the green dot 1 to where the camera starts and the red dot 2 to where it ends. The dashed frames show what the viewer sees first and last. The picture glides between them.
        With your own move you also choose "Moves closer", "Stays level" or "Moves wider", and "Swap start and end" reverses the direction. If the two dots are far apart the app zooms in enough to keep both inside the picture (at most about 2.4 times).
        Your camera choices are used in the full video, in Shorts and in the preview.
        """),
        HelpSection(id: "preview", title: "Preview and word timing", keywords: "preview watch captions words early late timing sync show sooner later nudge off fix the timing rough lyrics out of sync", body: """
        "Preview" (bottom left of the Pictures screen) plays the video as it will look, at a smaller size, before you make it. Nothing is saved. You can drag the words up or down to move them for the whole video.
        To make ALL the words (captions) of the song appear earlier or later (for example when every word seems to arrive after the singer): press "Preview", then under the preview press "Show sooner" (earlier) or "Show later" (later). On the Shorts page the same buttons under the vertical preview are named "Sooner" and "Later". They move the words only; they do not change where a Short starts or ends. Each press moves every word of the song by 0.05 seconds. The setting is saved with the song. "Reset" returns to the standard timing, which shows the words 0.06 seconds early.
        To correct only ONE lyric line: on the Pictures screen, click the part that contains the line and use the small −0.5s, −0.1s, +0.1s and +0.5s buttons next to that line. Those move just that line by half a second or a tenth of a second.
        If the top bar says "Word timing is rough", press "Fix the timing". The app listens to the song again to line every word up exactly (about a minute). Pictures are not touched.
        """),
        HelpSection(id: "making", title: "Making the video", keywords: "make video render export quality 1080 4k 720 save where file mp4 finished time how long cancel share finder clips", body: """
        "Make my video" (bottom right of the Pictures screen) creates the finished video. Parts without a picture get a plain colour background; the app asks before it does that.
        The button next to it shows the chosen sharpness (for example "1080p"). Press that button, and in the window that opens choose 720p, 1080p HD, 1440p or 4K, and tick or untick "Also make YouTube Shorts" (ticked by default). A new plan starts with suggested Shorts; if a song has none when you press "Make my video", the app cuts it into Shorts of about 30 seconds automatically. For older or open projects press "Make Shorts automatically" (above the pictures, or on the timeline) when a song has no Shorts. 1080p HD is right for YouTube; 4K takes much longer and makes a much bigger file.
        The video is made in the strip at the top of the window (a bar, "Main video" then "Short 2 of 5", the time taken and Cancel), and you can keep working meanwhile; changes you make go into the next video you make. When it is done, a green line says "Your video is ready" with a "Watch it" button that opens the Video screen. A four-minute song at 1080p usually takes one to a few minutes, depending on the Mac.
        If pictures are missing when you press "Make my video", the app offers "Draw the N missing pictures, then make the video" (it draws them and then makes the video by itself; if a drawing fails it stops and tells you), "Make it with colour backgrounds in the gaps", or "Keep working".
        The video is saved as "<song title>.mp4" in the folder next to the song's project folder (or in the separate folder you chose for finished videos in Settings).
        The last screen shows the video. "Show video in Finder" opens its folder. "Share" sends it by Messages, Mail or AirDrop. "Change something" goes back to the pictures. "Start a new video" starts over with a new song (this video stays saved).
        For YouTube: next to the video the app also saves "<song title> – thumbnail.jpg" (1280×720: the title card picture with the song title set on its quieter side and a "Lyric video" badge) and "<song title> – YouTube.txt" (a title, a description written for YouTube search with the full lyrics, tags and hashtags), written on your Mac for free. The Video screen shows the thumbnail with "Copy title", "Copy description", "Copy tags" and "Make them again".
        You can return to the finished video later by clicking Video at the top.
        """),
        HelpSection(id: "shorts", title: "YouTube Shorts: what they are and how to start", keywords: "shorts youtube vertical short clips tiktok reels 9:16 phone clip 30 seconds minute whole song start begin make add tabs", body: """
        On the Pictures screen, switch from "Full video" to "YouTube Shorts" at the top. A Short is a vertical video (1080 by 1920) that can be at most 3 minutes long.
        Your Shorts are tabs along the top of the Shorts page; press a tab to work on that Short. "Add a Short" (the plus) offers: "Cut my song into Shorts for me" (Shorts of about 30 seconds that start and end between the parts of your song), a new Short of about 30 seconds from the first words, or "Whole song" (the entire song as one vertical video, split into the fewest equal parts if it is longer than 3 minutes). The trash button deletes the selected Short. "Make all N Shorts" makes every Short, one after another.
        In this app "clip" only ever means a video clip in a picture's place (HeyGen or one you drag in); Shorts are always called Shorts.
        The page fits on one screen. On the left: the Short's name, the length pill, the whole-song map, a close-up of the start or the end, and the play buttons. On the right: the vertical preview, the look, and "Make this Short".
        Shorts are saved in the same folder as the main video, named "<song title> – <Short name>.mp4". Next to each there is a text file with a suggested title, description and hashtags, and a .json file with the Short's start and end times and the exact times of its words.
        """),
        HelpSection(id: "shortsTimeline", title: "Shorts: finding the part of the song (the song map and Browse the words)", keywords: "shorts select choose find part timeline map box drag move edges words browse click card start here end here chorus verse whole part thirty seconds waveform scroll zoom", body: """
        The whole song: picture sections are numbered blocks. Press a block to listen without changing the Short. Clicking outside the bright box also listens without moving it. Below the blocks is the whole song as a waveform. The bright box with the coloured outline is your Short; everything outside it is dimmed. Drag the box to move your Short, or drag its left or right edge to change where it starts or ends. This map is rough: it moves freely while you drag and settles on the nearest word or beat when you let go.
        "Browse the words" (under the close-up) opens a timeline of every word of the song in large type at the moment it is sung. Scroll it sideways and use the magnifier buttons to zoom. Click anywhere on it, or on a word, to hear the song from that spot; a small card appears there with "Start the Short here" and "End the Short here". You can also drag the green and red markers on it.
        "Make it ~30 s" keeps the start and adds lyric lines until the Short is about 30 seconds long.
        """),
        HelpSection(id: "shortsEnds", title: "Shorts: setting exactly where it starts and ends (including instrumental endings)", keywords: "shorts end ends ending start starts where stop finish instrumental music only after words last word exactly precise dial in earlier later beat nudge fade fading cut sharply loop snap snapping sticks beats words off shift hear switch", body: """
        Under the song map are two switches, "Where it starts" and "Where it ends", each showing its time. Press one to work on that end. The box below shows a close-up of that end: the waveform, the words, the beats of the music (small blue ticks), and the stretches with no words, tinted purple and marked "♪ music only".
        To set the end exactly, for example in the instrumental music after the last word: press "Where it ends", then click or drag anywhere on the close-up. The red marker goes there and you hear the last few seconds at once. The text above it says when the last word ends and how many seconds of music only follow it.
        The buttons under the close-up move that end: "◀ beat" and "beat ▶" jump to the previous or next beat; "−1 s", "−0.25 s", "−0.05 s" move it earlier and "+0.05 s", "+0.25 s", "+1 s" move it later. Every press plays the result so you can hear it. "Hear the ending" (or "Hear the start") plays that end again. The magnifier buttons zoom the close-up.
        Sticking: "Sticks to" (under the close-up) has four choices. Smart (the default) sticks to a word edge while words are being sung and to the nearest beat in music-only parts. Beats sticks only to beats. Words sticks only to word edges. Off keeps the marker exactly where you put it. Holding the Shift key while dragging also turns sticking off.
        "How it finishes" (shown when you work on the end): "Quick fade" (half a second), "Slow fade" (2 seconds, good for an instrumental ending), "Stop sharply" (no fade) or "Loop back to the start" (the last moment blends into the first so the Short repeats smoothly).
        Listening: "Play the Short" plays it from start to end (the space bar does the same; press it again to stop). "Repeat" (the L key) plays it again and again, starting half a second early.
        To hear just the part you selected: press "Play the Short" (or the space bar).
        To set where the Short ENDS (or starts): press "Where it ends" (or "Where it starts") and click or drag on the close-up; or drag the red (or green) edge of the bright box on the song map; or press "Later" style buttons such as "+0.25 s" to move that end a little.
        To make the end a little later: press "Where it ends", then one of the "+" buttons or "beat ▶".
        Note: the "Sooner" and "Later" buttons under the PREVIEW on the right move all the WORDS of the song (the captions), not the start or end of a Short.
        """),
        HelpSection(id: "shortsLength", title: "Shorts: the length colours and safe zones", keywords: "shorts length colour colours color pill orange green red grey seconds too short ideal 60 limit safe zones preview captions sooner later", body: """
        A pill at the top shows the length, for example "29.9 s / 60 s", and the line next to it says whether it is a good length. The colours mean:
        - Orange: under 5 seconds, too short for a compelling Short.
        - Grey: 5 to 15 seconds, a little short.
        - Green: 15 to 60 seconds, the ideal length.
        - Red: longer than 60 seconds (YouTube allows up to 3 minutes for some uploads).
        A Short can never be longer than 3:00 in this app.
        The preview on the right shows the vertical picture. "Safe zones" (on by default) shades the places where YouTube's own buttons and text cover the picture. Drag the captions in the preview to move them. "Sooner" and "Later" under the preview move all the words of the song a little earlier or later; they do not change where a Short starts or ends.
        """),
        HelpSection(id: "shortsLook", title: "Shorts: choosing the look", keywords: "shorts look style lively simple title hook closing text calm punchy pill pop big sweep surprise colour color beat pulse different look variants suggest more options make 3 versions", body: """
        The "Look" rows on the right have: "Lively" (an opening title, a highlight that follows each word, smooth picture changes) or "Simple" (plain pictures with the words at the bottom).
        With Lively: "Title" (the opening title; your song title when left empty; the sparkle button asks the AI for a catchy one), "Words" (Pill, Pop, Big, Sweep or Surprise) and "Colour" (coloured dots, or Auto).
        "More" has: Motion (Calm or Punchy), Beat pulse, Closing text, "Try a different look" (a new random look) and "Make 3 versions" (the same Short made three times with different looks).
        "Make this Short" creates the finished vertical video.
        The words in a Short always stay inside the middle of the picture, clear of YouTube's buttons at the sides; a line that is still too wide (a very long word) is made a little smaller. A Short has its own caption position: moving the words in a Short never moves them in the main video, and the other way round.
        """),
        HelpSection(id: "tips", title: "Mouseover tips and keyboard shortcuts", keywords: "tooltip tip hint mouseover hover point explain what does button keyboard shortcut space bar key L help", body: """
        Every button, switch, slider and picture in the app explains itself: rest the mouse pointer on it for about a second and a small yellow note appears saying what it does.
        Keyboard: the space bar plays or stops the Short; the L key plays it again and again; hold Shift while dragging a marker to turn sticking off.
        The "Help" button on every screen opens this guide and the question box. The strip across the top shows what you have spent on pictures.
        """),
        HelpSection(id: "videoClips", title: "Using a video clip instead of a picture", keywords: "video clip movie mp4 mov footage instead of picture animated moving own video drag", body: """
        Any part (and the title card) can show a video clip instead of a still picture. Drag an MP4 or MOV file into the picture box on the Pictures screen, or click the box and choose the file.
        The clip plays once while that part is on screen; if it is shorter than the part, its last picture holds and the camera moves over it (or switch on "Repeat the clip" to loop it with a smooth crossfade). It is cropped to fill the widescreen frame (or the tall Shorts frame). The clip's own sound is not used; your song keeps playing.
        Choosing which part of the clip plays: under the picture box, the "Video clip" panel shows a preview picture, a "Play this part" button, a strip of pictures from the clip and two cards, "Start of the clip" (green) and "End of the clip" (red).
        To start the clip later: drag the green START marker to the right, or press "+0.1 s" or "+0.5 s" on the Start card. To stop it earlier: drag the red END marker to the left, or press "−0.1 s" or "−0.5 s" on the End card. Everything outside the markers is dimmed and not used.
        To pick an exact moment: click a picture in the strip to look at that moment in the preview, then press "Start here" or "End here". "Play this part" shows the chosen stretch moving. "Use the whole clip" puts both markers back. By default the whole clip plays once. With "Repeat the clip" switched on, a part shorter than the song part repeats like a professional video loop: the end of the clip dissolves into its beginning, so there is no hard cut.
        The camera does not move while the clip plays; your camera choice applies to the held last picture after it. The thumbnail in the list is a still frame from it. "Choose a different file" or "Remove" puts back a picture. Clips work in the full video, in Shorts and in the preview. Widescreen clips (16:9) look best.
        Clips are copied into the song's folder, so the original can be moved or deleted afterwards.
        """),
        HelpSection(id: "reportBug", title: "Reporting a problem and seeing if it is fixed", keywords: "bug report problem error broken not working tell author feedback fixed status help contact send", body: """
        To tell the author about something that does not work, press "Help" ▸ "Report a Problem…" in the menu bar, or the "Report a problem" button in the Help window, or "Report this problem" on an error message.
        Write what you pressed and what happened, then press "Send report". You do not need an account. Only your text and the app version, macOS version and Mac type are sent (you can switch that off). Your songs, lyrics, files and keys are never sent.
        "My reports" lists everything you reported. Each shows "Received", "Being worked on" or "Done ✓", with the author's comment when there is one. "Check again" looks for news; the app also checks when it starts and tells you when something you reported is fixed.
        If sending is not set up in your copy of the app, "Copy my report" lets you paste it into an email or message.
        """),
        HelpSection(id: "pictureLook", title: "Bright pictures", keywords: "bright dark gloomy light colours colourful lighting mood sunny cheerful night", body: """
        The picture ideas the app writes are always bright, colourful and well lit, even for sad songs. The words "dark", "gloomy" and "night-time" are avoided, and every picture request ends with a reminder to be bright and cheerful.
        A picture style you chose (for example "Film Noir") can still look moody. If you want your own darker picture, drag it into the picture box.
        """),
        HelpSection(id: "storyCheck", title: "Picture ideas that follow the story (the story check)", keywords: "story logic check narrative forward previous idea physics continuity another idea rewrite changed local ai gemma", body: """
        When the app writes the picture ideas, each idea follows on from the picture before it and moves the story forward. After the ideas are first written, and after every "Another idea", the AI on your Mac runs a story check. It looks for ideas that show something physically impossible, that do not follow on from the idea before, or that do not fit the song at that moment, and rewrites only those. A blue note under the idea says what it changed and why. The check is free and never uses the internet.
        An idea you have edited yourself is never changed by the check, and pressing a generate button does not run the check. "Another idea" asks for a fresh idea again (and checks it).
        """),
        HelpSection(id: "styleGuide", title: "The style guide picture", keywords: "style guide reference picture look consistent same style title card match", body: """
        Every picture the app draws is matched to the look of one picture, the style guide, so the whole video looks like it belongs together. The title card is the style guide unless you choose another. Under any picture, "Use as the style guide" makes that picture the guide; the picture that is the guide shows "Style guide for all pictures". "Make all missing pictures" makes the guide first.
        Each new picture is also drawn from the picture before it (and the prompt names a specific camera view such as "a low angle from ground level", never the same as the pictures on either side): it keeps the same scene (place, people, objects, season) but shows it from a dramatically different camera angle and distance, and shows what its own idea describes. Sending a reference costs about half a cent each (a picture with both references costs about 1.9 cents in all). Pictures you drag in yourself are never changed.
        After a picture is drawn, a free check on your Mac compares its layout with the picture before it. If the framing is almost the same, an orange warning appears under the picture. Nothing is ever redrawn automatically: you decide whether to keep it or press "Try another picture". The check is a guide; it catches near-identical framing, not every similar picture.
        """),
        HelpSection(id: "heygenClips", title: "Video clips made by HeyGen (instead of Ken Burns)", keywords: "heygen video clip generate animate motion ken burns back to back whole section freeze price cost watch preview approve redo credit", body: """
        Every picture starts with Ken Burns (a slow pan and zoom), which is free. Under each picture, the "Motion" panel lets you make a video clip from the picture instead. Nothing is ever made automatically.
        - "Make this a video clip": the clip is as long as the section, rounded up to whole seconds, at least 5 and at most 15 seconds. The price is shown first. When the clip is ready you watch it in a small player and choose "Use this clip", "Redo" or "Discard".
        - A clip never loops by default. It plays once, exactly as made; then the last picture of the clip holds and the camera eases from the full frame onto the most prominent thing in it and moves steadily in toward the most prominent thing in it, leaning toward the second most prominent, in one direction. The app finds those two things on the clip's last frame with a tiny cloud check (a fraction of a cent).
        - Under each clip, "Choose the part that plays" has green START and red END markers, nudge buttons and "Play this part", the same as for a video you drag in. Trimming a clip in the middle of a back-to-back set closes the gap automatically. The camera buttons ("Automatic" / "I choose the move") are always available; with a clip in use your move runs over the clip's last picture.
        - "Repeat the clip until this part of the song ends (with a smooth crossfade)" is a switch, off by default. Turn it on to loop a single clip (generated or one you dragged in); the end blends into the beginning so there is no hard cut.
        - Sections shorter than 5 seconds still get a 5-second clip, trimmed to fit.
        - "Make the whole section as video" (only for sections over 15 seconds): clips of up to 15 seconds back to back, each starting on the last frame of the one before. It stops after each clip so you can watch it: "Looks good, make the next", "Redo this clip" or "Stop here". Tick "Make the rest without asking" to run it without stopping. "Continue with more video" adds clips later.
        - "Ken Burns" and "Video clip" above the panel switch a section between the two at any time for free; the clips are kept. "Delete clips" removes them.
        - "Make video clips for all pictures" (the bar above the pictures) makes one clip for every picture that has none, one after another, and uses each as soon as it arrives (you can still redo or trim any of them afterwards). It shows the total price and your OpenRouter credit first; the app refuses if the credit would not cover it.
        - Progress: every long task (drawing pictures, making clips, Shorts) shows in a strip at the very top of the window with a bar, the time taken and a Cancel button. HeyGen does not report progress, so a clip's bar is an estimate: it fills toward about 95% over the usual time and completes when the clip arrives. When a task finishes, a green "Done" line with its cost shows for a few seconds.
        - Prices shown are HeyGen's list price (currently $0.036 per second). While HeyGen's 50% promotion lasts the real charge is half; the green strip at the top shows what clips actually cost. There is no spending limit, but the app refuses to start a clip if your OpenRouter credit is lower than its price.
        - After each clip a cheap cloud check looks at five frames and shows an orange warning if something looks physically impossible. It only warns and never redoes anything. You can switch it off in Settings.
        """),
        HelpSection(id: "loopingVideo", title: "Looping long music video (study music, 1 to 12 hours)", keywords: "loop looping long video hours study music background seamless repeat 15 second scene clip title screen 1 3 8 12 hours ambient", body: """
        A separate kind of video: one song (any length) and one 15-second scene that loops seamlessly, made into a video of 1, 3, 8 or 12 hours (or any length from half an hour to 12 hours). On the first screen choose "Looping long music video" at the top, drag in the song, type its title and press "Start the looping video". It gets its own folder "<title> – looping video".
        1. The song: it repeats without a gap. The silence at its very start and end is cut, and its last 3 seconds blend into its beginning. "Title on the opening screen" is shown large at the start of the video and then fades into the loop (empty = the song title).
        2. The picture: the loop clip starts from it. Either use your own picture ("Use my own picture…" or drag it onto the box), or describe the scene and press "Draw the picture from the scene" (a few cents). "Suggest scenes" offers 10 calm scenes that loop well (free, written on your Mac). "Look" sets an art style. Earlier pictures appear as thumbnails; click one to use it again.
        "What moves" (under the picture): for every new picture the app looks at it once (a fraction of a cent) and writes what should move and how, for example "waves rolling onto the shore, clouds drifting very slowly; the rocks, beach and trees stay still". You can change it; it goes into the clip's instructions word for word. "Describe it from the picture" writes it again.
        3. The loop clip: HeyGen makes 15 seconds from the picture with a completely still camera; everything that would really move moves naturally (waves, water, rain, fire, leaves), clouds and the sky only very slowly (they drift one way, so slow drift keeps the loop's seam invisible), and people or animals only a little in place. Its end dissolves into its start, so it repeats without a visible seam. "Standard 768p" costs about $0.54 at list price, "Sharp 2K" about $1.50 (sharper in a 1080p video); HeyGen has been charging half during a promotion. You see the price first and the clip is collected even if the app is closed meanwhile. The box shows the loop playing exactly as it repeats in the long video. You can also loop your own video ("Use my own video clip…"); a still camera works best.
        4. The long video: choose the length and press "Make the long video". It is 1080p at about 1.7 GB per hour (12 hours ≈ 20 GB); the app checks there is enough free disk space first. Only about a minute of video is actually drawn (the opening, one loop and the ending); the rest is the same loop written again and again with the song looping underneath, so even 12 hours takes about a quarter of an hour. Progress shows in the strip at the top with Cancel, and you can keep working. It ends with a gentle fade-out. The file is saved as "<title> – <hours> (looping).mp4" in your finished-videos folder (or the project folder).
        For YouTube: with the long video the app also makes "<video name> – thumbnail.jpg" (1280×720, the picture with your title set on its quieter side, an "8 HOURS" badge and "Study · Focus · Relax") and "<video name> – YouTube.txt": a title, a description written for YouTube search (keywords first, chapters every hour) and tags and hashtags that are true for the video. They are written on your Mac, free. The "For YouTube" box shows the thumbnail and has "Copy title", "Copy description", "Copy tags" and "Make them again"; you can make them before the long video too.
        The picture and the clip are copied to your Pictures folder, and what they cost counts in "All songs together".
        """),
        HelpSection(id: "scaledTimeline", title: "The timeline: dragging pictures and Shorts", keywords: "timeline drag border picture split join shorts scale zoom lanes lyrics music interlude snap option delete double-click waveform", body: """
        At the top of the Song page ("Pictures & Shorts") and of the Pictures page is a timeline drawn to true scale: a time ruler with the waveform, the lyric lines at the moments they are sung, purple "music" blocks where nobody sings, the pictures, and the Shorts.
        - Drag the border between two pictures to move it; the pictures on either side grow and shrink. It snaps to the start or end of a lyric line; hold the Option key for no snapping.
        - Double-click the pictures row to add a border there. Click a border to select it and press the Delete key to join the two pictures. You can also right-click a border. "Undo" and "Redo" above the timeline cover every change.
        - On the Pictures page, moving a border changes only the timing. Each picture keeps its artwork and its video clips.
        - Drag a Short's middle to move it and its edges to resize it. Double-click the Shorts row to add a Short, and select one and press Delete to remove it. The length shown turns orange when it is too short and red when it is over 60 seconds. Picture changes never move Shorts.
        - "Fit the whole song", and the two magnifier buttons, change the zoom. Click a lyric line to hear it. The Pictures page can hide the timeline with the arrow next to "Timeline"; on a small screen it starts hidden.
        """),
        HelpSection(id: "focalPoints", title: "Two focal points and the automatic camera", keywords: "focal point focus subject camera ken burns move from to two subjects automatic travel", body: """
        Every picture idea has two focal points: two clearly different things you can see (for example a derrick and a group of workers), placed apart in the picture. Under the idea you see "The camera moves from … to …". The picture is drawn with both in view, and the app then finds where each one is in the finished picture (a cheap check, a fraction of a cent).
        The automatic camera moves from the first focal point to the second, zoomed in on each, at one steady pace in one direction. It never goes back and forth. Pictures you add yourself use the main subjects the app finds in them. A camera move you set yourself ("I choose the move") always wins.
        With a video clip, the prompt asks for the action and camera to travel from the first focal point toward the second (the first animates as it goes), and the same camera move continues over the clip and the frame after it.
        """),
        HelpSection(id: "picturesFolder", title: "The Pictures folder", keywords: "pictures folder library named date project number scroll find saved where files images copy", body: """
        Every picture, whether the app draws it or you add it, is also saved in one Pictures folder inside your main Music Videos folder, named with the date, the song and an increasing number, for example "2026-10-21 First Strike on the Caney River 007.png". The numbers only go up, so it is easy to scroll through them in Finder. Press "Pictures folder" at the top of the Pictures screen to open it, or the file name under a picture to show that picture in Finder. Video clips are saved there too, named after the picture they were made from: "2026-10-21 First Strike on the Caney River 007 clip 1.mp4" (then clip 2, …); videos you drag in are saved like pictures. Its menu also has "Add my earlier pictures and clips to it…", which copies the pictures and clips of every earlier song, and of the open one, that are not in the folder yet (oldest first, dated by when each was made; nothing is copied twice).
        Each song also keeps its own copy of its pictures, so a song stays complete when you move it; on a Mac's disk the second copy takes no extra space. Deleting a picture from the Pictures folder does not change the song.
        """),
        HelpSection(id: "steps", title: "Going back, new songs and earlier projects", keywords: "back go back previous step change song new project another song different mp3 open earlier project close start over", body: """
        The three steps at the top (Song, Pictures, Video) are buttons. Click Song to look at or change the title, setting and lyrics of the open video; click Pictures to return to the pictures; click Video to see the finished video again (it is available once you have made one).
        If you choose an MP3 with a different name than the video you are working on, the app starts a new video and the earlier one stays saved. A file with the same name keeps the current video.
        "Open earlier project" (first screen) goes back to any video you made before; choose its project folder or pick it from the recent list.
        "Close" (Pictures screen) closes the open video and returns to the first screen. Everything is saved automatically at every step.
        """),
        HelpSection(id: "files", title: "Where your files are", keywords: "folder files save location where saved project mp3 transcript lyrics prompts finder movies output", body: """
        By default everything is in the folder Movies/Music Videos. Each song gets its own folder with a project folder inside it named "<song title> – project". The project folder holds: project.mvproj (the save file with the parts, picture ideas, timing and camera choices), a copy of your song (audio.mp3), transcript files (what the AI heard), lyrics_synced.txt (your lyrics with the time each line is sung), prompts.md (all the picture ideas), and the folders full and thumbs with your pictures.
        The finished video and the Shorts are saved next to the project folder.
        Change the folder with "Saving to" on the first screen or in Settings under "Where things are saved" ("Main folder"). Under "Finished videos only" you can choose a different folder just for finished videos and Shorts.
        "Show folder" on the Pictures screen opens the song's folder in Finder.
        """),
        HelpSection(id: "settings", title: "Settings", keywords: "settings preferences options dock key folder updates models download again size small balanced best", body: """
        Open Settings with the gear button on the first screen or the Settings item in the app menu (Command and comma). It has these parts:
        - Where things are saved: the main folder and an optional separate folder for finished videos.
        - Picture maker (optional): your OpenRouter key and a "Check" button for your credit.
        - Updates: your version, "Check for updates", "Versions & rollback…", "Stay on this version" and "Resume updates".
        - Shortcuts & help: "Add to Dock" or "Remove from Dock", "Fix recording permission…" and "Show Quick Guide".
        - On-device AI: the two models the app uses (Parakeet Ultra and the language model), whether each is downloaded, and a "Download again" button for each. The size picker (Small, Balanced, Best) chooses which language model is downloaded.
        """),
        HelpSection(id: "models", title: "On-device AI models and the first download", keywords: "models download parakeet gemma language model gb size first launch setup offline internet storage space", body: """
        The first time the app opens it downloads two models to your Mac: Parakeet Ultra (about 0.5 GB), which finds when each word is sung, and a language model (Gemma 4 E2B, about 3.6 GB in the Balanced size) which writes the description, picture ideas and suggestions. After that the app works without internet, except for the optional picture maker and update checks.
        The setup screen shows each model and a live percentage while it downloads. You can see them at any time in Settings under On-device AI.
        If planning stops with an error about the language model, open Settings, find the language model and press "Download again".
        Sizes: Small (about 1 GB, fastest, plainer picture ideas), Balanced (about 3.6 GB, recommended), Best (about 6 GB, needs more memory).
        """),
        HelpSection(id: "updates", title: "Updates", keywords: "update version new release install latest upgrade restart check rollback revert downgrade skip unskip stay pin hold versions backup", body: """
        The app checks GitHub about once a day and offers a newer version; it never installs without your choice. "What's new" shows the notes. "Update now" verifies the checksum, installs and restarts. "Later" hides the strip until next launch. "Skip this version" stops automatic prompts for that release; later releases can still be offered.
        In Settings, Updates, choose "Versions & rollback…" (or "Versions & Rollback…" in the app menu). Available stable standalone releases with checksums are listed with their notes. Choose "Install this version…" or "Revert to this version…", then confirm "Install and restart". Internet is required. Releases requiring newer macOS cannot be installed.
        "Stay on this version" pauses automatic update prompts until "Resume updates" or "Resume update notifications". Skipped versions can be unskipped, individually or with "Clear skipped versions". Manual version selection remains available.
        Reverting automatically selects staying on that older version. Apps released before these controls may not show a Versions screen; use their Check for Updates command to return to a newer release.
        Finish or cancel listening, picture generation and video rendering before changing versions. The open project and its referenced media are backed up under its "Version Backups" folder before installing. Pictures and audio are copied into the backup so older apps cannot delete the backup copies. Earlier apps may not understand newer editing fields; keep the backup if returning to a newer app. A checksum or validation failure leaves the current app in place. If the swap cannot finish, the installer restores the previous app.
        Install the app in a writable Applications folder to let it replace itself.
        """),
        HelpSection(id: "recording", title: "Recording problems (macOS permission)", keywords: "record recording permission screen system audio microphone blocked cant record privacy security settings fix", body: """
        "Record it as it plays" with "System audio" needs the macOS permission "Screen & System Audio Recording". If recording says macOS is blocking it even though the switch in System Settings is on, open Settings ▸ "Fix recording permission…" (or follow the window that opens by itself): press "Fix it for me", switch Music Video Maker on in the list that opens, then press "Restart the app".
        "Use microphone instead" in that window records through a microphone or audio input and needs no screen permission (the microphone permission is needed).
        """),
        HelpSection(id: "troubleshooting", title: "Common problems and fixes", keywords: "problem error trouble wrong not working stuck fails blank colour gradient plain background missing picture cant click disabled warning lyrics match slow", body: """
        - The "Plan my video" button is grey: you need a song, a title and lyrics.
        - Words appear too early or late: use "Show sooner" or "Show later" under the preview; if the top bar says the timing is rough press "Fix the timing".
        - Some parts of the video show a plain colour: those parts have no picture. Add pictures, or press "Make all missing pictures".
        - "Lyrics only N% matched": the lyrics you pasted differ from what is sung. Check the words and plan again as a new video.
        - An error about the language model: Settings ▸ On-device AI ▸ "Download again" next to the language model.
        - Recording is blocked: Settings ▸ "Fix recording permission…".
        - The picture maker says no key or no credit: add the key under "Picture maker key & credit" and check your OpenRouter credit.
        - The window is too big for a small screen: the window resizes to fit; it can be as small as 860 by 560.
        - The app cannot update itself: move it to the Applications folder, or install the newest version again with the install command.
        """),
        HelpSection(id: "limits", title: "What the app cannot do", keywords: "cannot cant not possible impossible limit limitation unsupported support windows intel upload youtube edit timeline transitions font translate", body: """
        These things are not possible in this app:
        - It does not edit video: it does not rearrange or cut the source audio. You can split and join picture sections and continuous Shorts. A video clip can be placed in a section instead of a picture and trimmed (it repeats if it is shorter than the part, it is cropped to fill the frame, its own sound is not used).
        - It makes one video from one song. It cannot combine several songs into one video.
        - It cannot upload to YouTube; it only creates the files (and suggested titles and descriptions for Shorts).
        - The full video's lyric style (font and layout) is fixed; you can move the words up or down in the preview. Word styles and colours can be chosen only for Shorts.
        - You cannot choose the transitions between pictures by hand; they are chosen automatically.
        - It cannot translate lyrics, and the words on screen are always exactly the words you typed.
        - It cannot edit or enhance the audio. The only audio change is cutting silence at the start and end of a recording.
        - The picture maker cannot work without internet, an OpenRouter key and paid credit. Without it, you add your own pictures.
        - It needs a Mac with Apple Silicon (M1 or newer) and macOS 14 or newer. It does not run on Windows or on Intel Macs.
        - A YouTube Short cannot be longer than 3 minutes.
        - A Short is one continuous stretch of the song. You cannot join separate parts of the song into one Short ("Whole song" makes the entire song instead).
        - Video sharpness choices are 720p, 1080p, 1440p and 4K; the frame rate is fixed.
        - The assistant in Help only knows what this guide says and what is on your screen.
        """),
    ]

    // MARK: finding the right sections for a question

    private static let stop: Set<String> = ["the", "and", "for", "how", "can", "what", "does", "this", "that", "with", "you", "your", "are", "was", "why", "when", "where", "which", "from", "have", "has", "not", "but", "its", "into", "out", "about", "would", "could", "should", "there", "they", "them", "then", "than", "just", "also", "any", "all", "get", "got", "make", "need", "want", "like", "using", "use", "app", "please", "tell", "show", "does", "doing", "done", "way", "able"]

    static func words(_ t: String) -> Set<String> {
        Set(t.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 3 && !stop.contains($0) }.map(stem))
    }
    static func stem(_ w: String) -> String {
        for suffix in ["ing", "ed", "es", "s"] where w.hasSuffix(suffix) && w.count - suffix.count >= 4 { return String(w.dropLast(suffix.count)) }
        return w
    }

    /// The sections whose words overlap the question most (best first). Empty when nothing in the guide relates to it.
    static func relevant(to question: String, top: Int = 4) -> [HelpSection] {
        let q = words(question)
        guard !q.isEmpty else { return [] }
        let scored: [(HelpSection, Double)] = sections.map { s in
            let kw = words(s.keywords), title = words(s.title), body = words(s.body)
            var score = 0.0
            for w in q { if kw.contains(w) { score += 3 }; if title.contains(w) { score += 2.5 }; if body.contains(w) { score += 1 } }
            return (s, score)
        }
        return scored.filter { $0.1 >= 2 }.sorted { $0.1 > $1.1 }.prefix(top).map(\.0)
    }

    static func section(_ id: String) -> HelpSection? { sections.first { $0.id == id } }
}
