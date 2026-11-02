// The small script that replaces the app during an update, after the running copy has quit.
import Foundation

public enum UpdateSwap {
    /// Arguments: quitting app's PID, new app, installed app, backup path, work folder, test root, test prefs, failure note file, version, then optionally
    /// how many half-seconds to wait for the new version to appear and to stay running. `open` only says the request was accepted, so the backup
    /// is kept until the new version is seen running and is still running 15 seconds later; otherwise the previous version is put back.
    public static let script = """
    #!/bin/sh
    PID="$1"; NEW="$2"; DEST="$3"; BACKUP="$4"; WORK="$5"; TESTROOT="$6"; TESTPREFS="$7"; NOTE="$8"; VERSION="$9"
    APPEAR="${10:-60}"; STAY="${11:-30}"
    launch() {
      if [ -n "$TESTROOT" ]; then
        open -n "$DEST" --env "MV_EDITOR_SELFTEST=ui" --env "MV_TEST_ROOT=$TESTROOT" --env "MV_TEST_PREFS=$TESTPREFS" --env "MV_DEMO_PLAN=$TESTROOT/project"
      else open "$DEST"; fi
    }
    running() { pgrep -f "$DEST/Contents/MacOS/" >/dev/null 2>&1; }
    started() {
      [ -n "$TESTROOT" ] && return 0
      i=0; while ! running; do i=$((i+1)); [ "$i" -ge "$APPEAR" ] && return 1; sleep 0.5; done
      i=0; while [ "$i" -lt "$STAY" ]; do sleep 0.5; running || return 1; i=$((i+1)); done
      return 0
    }
    while kill -0 "$PID" 2>/dev/null; do sleep 0.2; done
    if mv "$DEST" "$BACKUP"; then
      if mv "$NEW" "$DEST"; then
        if launch && started; then rm -rf "$BACKUP"
        else
          pkill -f "$DEST/Contents/MacOS/" 2>/dev/null
          mv "$DEST" "$WORK/failed.app"; mv "$BACKUP" "$DEST"
          [ -n "$NOTE" ] && printf '%s' "$VERSION" > "$NOTE"
          launch
        fi
      else mv "$BACKUP" "$DEST"; launch; fi
    else launch; fi
    rm -rf "$WORK"
    """
}
