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
        Music Video Maker turns a song and its lyrics into a finished music video (an MP4 file) and, if you want, short vertical clips for YouTube Shorts.
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
        By default the app makes one picture for every verse and one for every music break (music with no singing, 4 seconds or longer). A verse is never split by default. A music break longer than 40 seconds is split into equal pictures of no more than 30 seconds. A break shorter than 4 seconds belongs to the verse next to it.
        Where verses start: your own cuts first, then your verse marks (blank lines, `---`, tags such as [Chorus]); with neither, every run of singing between two music breaks is a verse, and a run longer than 45 seconds is cut at its longest pauses.
        To see and change this, press "Divide into parts" above the lyrics box. The first time, press "Listen to the song first (about a minute)": the app finds when every line is sung and where the music-only breaks are (it does not write picture ideas and nothing is spent). "Plan my video" afterwards reuses that listening. If you change the song or the words, listen again.
        The timeline then shows the song from top to bottom:
        - Each lyric line has its time (for example 1:12) and a play button to hear it.
        - A purple "♪ Music — no singing" block with its time range and length is a music break. It has its own picture and a play button.
        - Each picture is a coloured bar such as "Picture 4 · 0:33–0:55 · 22 s · 4 lines". At the top you see how many pictures there are and about what they cost to draw.
        - Between two lines there is a "cut here" line. Click it to start a new picture at that point.
        - "Split in two" on a picture's bar cuts that picture into two pictures of about the same length, between two lines. Press it again to split further.
        - "Join with above" on a picture's bar removes its cut, so the lines share the picture above.
        - "Split long verses" splits every verse longer than 30 seconds into pictures of about 20 to 30 seconds.
        - "Start over" removes your own cuts, so the pictures follow your verse marks and the music breaks again.
        - Once the video is planned, a thin blue bar on the right shows which lines each Short covers ("Short 2"). Fine-tune a Short on the Shorts page.
        In the text, a cut is a line containing three dashes (---).
        Anything written in brackets, [like this], {this}, <this> or (this), is never used: it is not shown in the captions and not used for the picture ideas. A tag on a line of its own, such as [Chorus], still marks the start of a verse.
        YouTube Shorts made automatically also start and end between parts, never in the middle of one (a part much longer than a Short is split at its pauses).
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
        - "Picture for this part": drag a picture or a video clip (MP4 or MOV) into the box or click it to choose a file. Use widescreen pictures (16:9), 1920 by 1080 pixels or larger. Other shapes are cropped to fit and the app warns you.
        - "Make this picture for me" draws the picture with the picture maker (needs an OpenRouter key, costs a few cents). "Try another picture" draws a new one. "Choose a different file" and "Remove picture" are under the box.
        - "Camera": see the section "Camera movement".
        Parts that are only music have names like "Music before the words", "Music break" and "Music after the words" and get their own picture idea.
        The first item, "Title card", is the opening picture behind the song title.
        The bar above the pictures shows what to do next and these buttons: "Make all missing pictures", "Setting & description", "Art style", "Picture maker key & credit" and "Copy all picture ideas".
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
        - "Automatic": the camera sweeps quickly across the whole picture, edge to edge, ending on the most interesting part (the direction changes from one picture to the next, and now and then it glides diagonally). You can drag the orange dot to aim it, or press "Aim for me" to let the app find the spot. "Show the aim" shows the dot and the dashed box that is kept in the tall YouTube Shorts version.
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
        The button next to it shows the chosen sharpness (for example "1080p"). Press that button, and in the window that opens choose 720p, 1080p HD, 1440p or 4K, and tick or untick "Also make short clips for YouTube Shorts". 1080p HD is right for YouTube; 4K takes much longer and makes a much bigger file.
        A progress screen shows the percentage and time left, and you can cancel. A four-minute song at 1080p usually takes one to a few minutes, depending on the Mac.
        The video is saved as "<song title>.mp4" in the folder next to the song's project folder (or in the separate folder you chose for finished videos in Settings).
        The last screen shows the video. "Show video in Finder" opens its folder. "Share" sends it by Messages, Mail or AirDrop. "Change something" goes back to the pictures. "Start a new video" starts over with a new song (this video stays saved).
        You can return to the finished video later by clicking Video at the top.
        """),
        HelpSection(id: "shorts", title: "YouTube Shorts: what they are and how to start", keywords: "shorts youtube vertical short clips tiktok reels 9:16 phone clip 30 seconds minute whole song start begin make add tabs", body: """
        On the Pictures screen, switch from "Full video" to "YouTube Shorts" at the top. A Short is a vertical video (1080 by 1920) that can be at most 3 minutes long.
        Your clips are tabs along the top of the Shorts page; press a tab to work on that clip. "Add a clip" (the plus) offers: "Cut my song into clips for me" (clips of about 30 seconds that start and end between the parts of your song), a new clip of about 30 seconds from the first words, or "Whole song" (the entire song as one vertical video, split into the fewest equal parts if it is longer than 3 minutes). The trash button deletes the selected clip. "Make all N clips" makes every clip, one after another.
        The page fits on one screen. On the left: the clip's name, the length pill, the whole-song map, a close-up of the start or the end, and the play buttons. On the right: the vertical preview, the look, and "Make this clip".
        Shorts are saved in the same folder as the main video, named "<song title> – <clip name>.mp4". Next to each there is a text file with a suggested title, description and hashtags, and a .json file with the clip's start and end times and the exact times of its words.
        """),
        HelpSection(id: "shortsTimeline", title: "Shorts: finding the part of the song (the song map and Browse the words)", keywords: "shorts select choose find part timeline map box drag move edges words browse click card start here end here chorus verse whole part thirty seconds waveform scroll zoom", body: """
        The whole song: the song's parts are coloured blocks. To use a whole part (for example a chorus) as your Short, press its block. Below the blocks is the whole song as a waveform. The bright box with the coloured outline is your Short; everything outside it is dimmed. Drag the box to move your Short, or drag its left or right edge to change where it starts or ends. This map is rough: it moves freely while you drag and settles on the nearest word or beat when you let go.
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
        "More" has: Motion (Calm or Punchy), Beat pulse, Closing text, "Try a different look" (a new random look) and "Make 3 versions" (the same clip made three times with different looks).
        "Make this clip" creates the finished vertical video.
        """),
        HelpSection(id: "tips", title: "Mouseover tips and keyboard shortcuts", keywords: "tooltip tip hint mouseover hover point explain what does button keyboard shortcut space bar key L help", body: """
        Every button, switch, slider and picture in the app explains itself: rest the mouse pointer on it for about a second and a small yellow note appears saying what it does.
        Keyboard: the space bar plays or stops the Short; the L key plays it again and again; hold Shift while dragging a marker to turn sticking off.
        The "Help" button on every screen opens this guide and the question box. The strip across the top shows what you have spent on pictures.
        """),
        HelpSection(id: "videoClips", title: "Using a video clip instead of a picture", keywords: "video clip movie mp4 mov footage instead of picture animated moving own video drag", body: """
        Any part (and the title card) can show a video clip instead of a still picture. Drag an MP4 or MOV file into the picture box on the Pictures screen, or click the box and choose the file.
        The clip plays while that part is on screen. If the clip is shorter than the part it plays again from the start. It is cropped to fill the widescreen frame (or the tall Shorts frame). The clip's own sound is not used; your song keeps playing.
        Choosing which part of the clip plays: under the picture box, the "Video clip" panel shows a preview picture, a "Play this part" button, a strip of pictures from the clip and two cards, "Start of the clip" (green) and "End of the clip" (red).
        To start the clip later: drag the green START marker to the right, or press "+0.1 s" or "+0.5 s" on the Start card. To stop it earlier: drag the red END marker to the left, or press "−0.1 s" or "−0.5 s" on the End card. Everything outside the markers is dimmed and not used.
        To pick an exact moment: click a picture in the strip to look at that moment in the preview, then press "Start here" or "End here". "Play this part" shows the chosen stretch moving. "Use the whole clip" puts both markers back. By default the whole clip plays. If the chosen part is shorter than the song part it repeats like a professional video loop: the end of the clip dissolves into its beginning (about half a second), so there is no hard cut.
        The camera moves do not apply to a video clip. The thumbnail in the list is a still frame from it. "Choose a different file" or "Remove" puts back a picture. Clips work in the full video, in Shorts and in the preview. Widescreen clips (16:9) look best.
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
        - Updates: your version, whether an update is waiting, and "Check for updates".
        - Shortcuts & help: "Add to Dock" or "Remove from Dock", "Fix recording permission…" and "Show Quick Guide".
        - On-device AI: the two models the app uses (Parakeet Ultra and the language model), whether each is downloaded, and a "Download again" button for each. The size picker (Small, Balanced, Best) chooses which language model is downloaded.
        """),
        HelpSection(id: "models", title: "On-device AI models and the first download", keywords: "models download parakeet gemma language model gb size first launch setup offline internet storage space", body: """
        The first time the app opens it downloads two models to your Mac: Parakeet Ultra (about 0.5 GB), which finds when each word is sung, and a language model (Gemma 4 E2B, about 3.6 GB in the Balanced size) which writes the description, picture ideas and suggestions. After that the app works without internet, except for the optional picture maker and update checks.
        The setup screen shows each model and a live percentage while it downloads. You can see them at any time in Settings under On-device AI.
        If planning stops with an error about the language model, open Settings, find the language model and press "Download again".
        Sizes: Small (about 1 GB, fastest, plainer picture ideas), Balanced (about 3.6 GB, recommended), Best (about 6 GB, needs more memory).
        """),
        HelpSection(id: "updates", title: "Updates", keywords: "update version new release install latest upgrade restart check", body: """
        When a new version exists, a blue "Update available" strip appears across the top of the window. "What's new" shows the changes, "Update now" downloads and installs it and restarts the app, and "Later" hides the strip until you open the app again. Your songs, pictures and settings are kept.
        You can also use Check for Updates in the app menu or the Help menu, or Settings ▸ Updates. The app checks by itself about once a day.
        The app must be in the Applications folder to update itself.
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
        - It does not edit video: no timeline and no cutting or joining. A video clip can be placed in a part instead of a picture, but it is used as it is (it repeats if it is shorter than the part, it is cropped to fill the frame, its own sound is not used).
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
