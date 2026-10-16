pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."

// The events Omarchy syncs from the user's calendars, read straight from the
// file the stock calendar widget writes and reads too
// (~/.local/state/omarchy/calendar-events.json) -- nothing here polls or
// syncs; one FileView watches it for the whole shell:
//
//   { "lastSynced": 1792077118,
//     "eventsByDate": { "2026-10-16": [ { title: "Gabinet 103",
//                                        startTime: "12:00", endTime: "13:00",
//                                        allDay: false, calendar: "...",
//                                        color: "#4A90E2", location: "...",
//                                        description: "..." } ] } }
//
// Mainly the dashboard's calendar: a dot under every day that has one, and
// today's events under the grid. A missing or unparsable file answers empty,
// so a calendar that has never synced leaves the calendar card untouched.
QtObject {
  id: root

  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"
  readonly property string path: root.stateHome + "/omarchy/calendar-events.json"
  // "" while the file has not loaded: every lookup then answers empty.
  property var eventsByDate: ({})

  function load() {
    try {
      const data = JSON.parse(file.text())
      root.eventsByDate = data && typeof data.eventsByDate === "object" && data.eventsByDate ? data.eventsByDate : ({})
    } catch (e) {
      root.eventsByDate = ({})
    }
  }

  property FileView file: FileView {
    path: root.path
    watchChanges: true
    printErrors: false
    onLoaded: root.load()
    // text() is still stale inside onFileChanged; reload and parse on onLoaded.
    onFileChanged: reload()
    onLoadFailed: root.eventsByDate = ({})
  }

  // The file's key for a day, in local time: "YYYY-MM-DD".
  function key(date) {
    return Qt.formatDate(date, "yyyy-MM-dd")
  }
  // The day's events, as the file holds them (a shared list, so a binding that
  // reads it is only re-evaluated when the file is reread).
  function eventsOnKey(dayKey) {
    const list = root.eventsByDate[dayKey]
    return Array.isArray(list) ? list : []
  }
  function events(date) {
    return root.eventsOnKey(root.key(date))
  }
  function count(date) {
    return root.eventsOnKey(root.key(date)).length
  }
}
