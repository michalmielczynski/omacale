import QtQuick

// Stands in for Quickshell's SystemClock, which Caelestia uses. Two reasons.
//
// 1. SystemClock schedules its next tick from local wall time. In the hour
//    repeated when daylight saving ends, that target resolves to the first
//    pass through the hour, so the delay comes out negative, the timer rearms
//    at 1 ms with a warning and the log floods for the whole hour. (Omarchy's
//    own plugins/panels/clock/WallClock.qml exists for this reason.)
// 2. Timers run on CLOCK_MONOTONIC, which does not advance while the machine
//    sleeps. A tick armed for the next minute still waits out the rest of that
//    minute after a resume, so the bar, the lock screen and the desktop clock
//    showed the pre-suspend time for up to a minute.
//
// Both go away by looking at the wall clock once a second: epoch milliseconds
// never repeat, so a resume (or a DST change, or an NTP step) is on screen
// within a second. `date` is only reassigned when the slice on show changes, so
// a minute clock still touches its bindings once a minute; the one wake a
// second is what the bar already pays for its lock-key poll.
Timer {
  id: root

  // Milliseconds between ticks: 1000 to show seconds, 60000 for minutes.
  property int step: 60000
  property date date: new Date()

  // The slice of the epoch (step wide) that `date` is showing.
  property real slice: 0

  interval: 1000
  repeat: true
  running: true

  function nowSlice() {
    return Math.floor(Date.now() / step)
  }

  function resync() {
    slice = nowSlice()
    date = new Date()
  }

  // A new step (the bar's seconds setting, say) shows at once, not on the
  // next tick.
  onStepChanged: resync()
  Component.onCompleted: resync()
  onTriggered: {
    if (nowSlice() === slice)
      return
    resync()
  }
}
