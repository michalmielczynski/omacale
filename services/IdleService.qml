pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."
// IdleService: Manages Omarchy idle behavior / keep awake mode.
// Integrates directly with Omarchy's indicators/stay-awake and idle engine.
//
// Keep awake can also be set for a while (15 / 30 / 60 minutes, as GNOME's
// Caffeine), since Omarchy's toggle is all-or-nothing: the deadline is kept
// in $XDG_STATE_HOME/omacale/keep-awake-until, so a timer started before a
// shell restart still ends when it should, and keep awake turned on by an
// Omarchy command (SUPER+CTRL+I) is always open-ended.
QtObject {
  id: root

  property bool enabled: false
  property var enabledSince: null

  // A timed keep awake: `expiresAt` is when it ends, `remaining` counts down
  // to it (seconds), and `timedMinutes` is the preset it was started from
  // (0 for one started before a shell restart, or for an open-ended one).
  property bool timed: false
  property var expiresAt: null
  property int remaining: 0
  property int timedMinutes: 0

  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omacale"
  readonly property string untilPath: stateDir + "/keep-awake-until"

  // What the utilities card's pill reads ("Auto-off in 12 min").
  readonly property string remainingText: {
    if (!root.enabled || !root.timed) return ""
    const s = root.remaining
    if (s <= 0) return "less than a minute"
    if (s < 60) return s + " s"
    const m = Math.ceil(s / 60)
    if (m < 60) return m + " min"
    const h = Math.floor(m / 60)
    const mm = m % 60
    return h + " h" + (mm > 0 ? " " + mm + " min" : "")
  }

  // A timer restored at startup is only applied once both state files have
  // been read: the indicator's first load must not look like a manual toggle
  // (it would drop the deadline), and an absent deadline file must not look
  // like "no timer" before it has been checked either.
  // Bar.qml touches this at startup, so the singleton exists (and a restored
  // timer keeps running) even if the utilities card is never opened.
  readonly property bool alive: true

  property bool started: false
  property bool indicatorKnown: false
  property bool deadlineKnown: false
  property bool restored: false

  function run(cmd) { Quickshell.execDetached(["bash", "-c", cmd]) }

  function toggle() {
    if (enabled) disable()
    else enable()
  }

  // `minutes` 0 (or nothing) keeps the screen awake until it is turned off;
  // anything else ends it after that many minutes.
  function enableFor(minutes) {
    const m = Math.max(0, Math.round(Number(minutes) || 0))
    root.timed = m > 0
    root.timedMinutes = m
    root.expiresAt = m > 0 ? new Date(Date.now() + m * 60000) : null
    root.remaining = m * 60
    setEnabled(true)
    writeDeadline(root.expiresAt ? root.expiresAt.getTime() : 0)
    run("omarchy-toggle-idle stay-awake >/dev/null")
  }

  // The same command SUPER+CTRL+I runs (`omarchy toggle idle`); Omarchy's
  // idle service follows the indicator file it writes. Not `omarchy-shell
  // idle enable/disable`: those mean *allow* idle / stay awake, the reverse
  // of what they read as, and pairing them with the file undid every click.
  function enable() { root.enableFor(0) }

  function disable() {
    setEnabled(false)
    writeDeadline(0)
    run("omarchy-toggle-idle allow-idle >/dev/null")
  }

  // Keep awake is the presence of Omarchy's indicator file, so read it
  // rather than asking a shell whether it exists: this used to be a
  // `bash -c` every 3s for the whole session to answer "no" each time.
  function setEnabled(on) {
    if (root.enabled === on)
      return
    root.enabled = on
    if (on) {
      if (!root.enabledSince)
        root.enabledSince = new Date()
    } else {
      root.enabledSince = null
      root.timed = false
      root.expiresAt = null
      root.remaining = 0
      root.timedMinutes = 0
      // Switched off from outside Omacale: nothing is counting down any more.
      if (root.restored)
        writeDeadline(0)
    }
  }

  function writeDeadline(ms) {
    if (ms > 0)
      run("mkdir -p \"" + root.stateDir + "\" && printf '%s' " + ms + " > \"" + root.untilPath + "\"")
    else
      run("rm -f \"" + root.untilPath + "\"")
  }

  // The show is over: turn keep awake off, and say so (unless the shell was
  // down when it ran out, which `notify` skips).
  function expire(notify) {
    if (notify && Config.o.utilities.toasts.keepAwakeEnded)
      Toaster.toast("Keep awake ended", "Sleep mode is back on", "coffee", Toaster.info, 5000, "omacale:keep-awake-ended")
    disable()
  }

  function tick() {
    if (!root.enabled || !root.timed || !root.expiresAt) {
      root.remaining = 0
      return
    }
    const left = Math.max(0, Math.ceil((root.expiresAt.getTime() - Date.now()) / 1000))
    root.remaining = left
    if (left <= 0)
      root.expire(true)
  }

  function maybeRestore() {
    if (root.restored || !root.started || !root.indicatorKnown || !root.deadlineKnown) return
    root.restored = true
    root.restore()
  }

  // A deadline saved by an earlier shell: a future one carries the timer on,
  // an expired one means keep awake ran out while the shell was restarting.
  function restore() {
    const n = root.deadline.loaded ? parseInt(String(root.deadline.text()).trim(), 10) : NaN
    if (!root.enabled) {
      // Keep awake is off, so nothing can be counting down.
      root.timed = false
      root.expiresAt = null
      if (isFinite(n)) writeDeadline(0)
      return
    }
    if (!isFinite(n)) {
      // No deadline: keep awake was switched on by hand.
      root.timed = false
      root.expiresAt = null
      return
    }
    if (n > Date.now()) {
      root.timed = true
      root.timedMinutes = 0
      root.expiresAt = new Date(n)
      root.tick()
    } else {
      root.expire(false)
    }
  }

  property FileView indicator: FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/indicators/stay-awake"
    printErrors: false
    onLoaded: {
      root.indicatorKnown = true
      root.setEnabled(true)
      root.maybeRestore()
    }
    onLoadFailed: {
      root.indicatorKnown = true
      root.setEnabled(false)
      root.maybeRestore()
    }
  }

  // The indicator file is created and deleted rather than written, so the
  // watch has to be on the directory holding it.
  property FileView indicatorWatcher: FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/indicators"
    watchChanges: true
    printErrors: false
    onFileChanged: root.indicator.reload()
  }

  // Read once, at startup: after that the deadline lives in this service
  // (and is written back whenever it changes), so watching the file would
  // only ever feed our own writes back in.
  property FileView deadline: FileView {
    path: root.untilPath
    printErrors: false
    onLoaded: {
      root.deadlineKnown = true
      root.maybeRestore()
    }
    onLoadFailed: {
      root.deadlineKnown = true
      root.maybeRestore()
    }
  }

  property Timer ticker: Timer {
    interval: 1000
    repeat: true
    running: root.enabled && root.timed
    triggeredOnStart: true
    onTriggered: root.tick()
  }

  property Timer startup: Timer {
    interval: 1200
    running: true
    onTriggered: {
      root.started = true
      root.maybeRestore()
    }
  }

  // Safety net for a change the directory watch misses (the directory itself
  // being created, most of all -- a machine that has never used keep awake
  // has nothing there to watch).
  property Timer checkTimer: Timer {
    interval: 30000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.indicator.reload()
  }
}
