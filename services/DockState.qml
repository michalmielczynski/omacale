pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import ".."

// What the dock's icons say about their apps beyond "running": a badge, a
// progress bar, and the urgent wiggle. Three sources, one place.
//
//  * Omarchy's notification daemon, through NotifService (the state files
//    Omarchy writes): the badge is macOS's reading -- notifications count
//    until the app is focused again -- so the count is compared with what it
//    was when the app last had focus, not with a separate "read" flag.
//  * The Unity LauncherEntry signal (com.canonical.Unity.LauncherEntry), which
//    Thunderbird, Telegram and the Electron apps emit for their own count,
//    progress and urgent. Quickshell has no D-Bus client, so a dbus-monitor
//    process watches that one interface and the signal blocks are parsed here.
//    Unity's count wins over ours; its progress is the only progress there is.
//  * Hyprland's `urgent` event, for a window asking for attention.
//
// Everything is keyed by the dock's own key ("app:<desktop id>" or
// "class:<class>"), so the caller only asks badgeFor(key) / progressFor(key) /
// urgentFor(key) and never sees a desktop id.
QtObject {
  id: root

  readonly property var cfg: Config.o.dock
  readonly property bool badgesOn: cfg.badges !== false
  readonly property bool progressOn: cfg.progress !== false
  readonly property bool urgentOn: cfg.urgent !== false
  readonly property bool watching: root.badgesOn || root.progressOn

  // ------------------------------------------------------------ the keys
  // A notification names its sender, not a desktop entry ("kitty", "Spotify").
  // The dock's own lookup already knows every class and StartupWMClass, so the
  // name is matched against what the items carry. An app that is in no item
  // (not pinned, not running) has no icon to badge.
  function norm(v) { return WindowIcons.norm(String(v || "")) }

  function keyForAppName(name) {
    const n = root.norm(name)
    if (!n) return ""
    const items = DockService.items
    for (let i = 0; i < items.length; i++) {
      const it = items[i]
      if (it.id && root.norm(it.id) === n) return it.key
      if (root.norm(it.name) === n) return it.key
      const e = it.entry
      if (e && e.startupClass && root.norm(e.startupClass) === n) return it.key
    }
    return ""
  }

  function keyForDesktopId(id) {
    if (!id) return ""
    const bare = String(id).replace(/\.desktop$/i, "")
    const e = DockService.entryById(String(id)) || DockService.entryById(bare + ".desktop")
    if (e) return "app:" + e.id
    const items = DockService.items, n = root.norm(bare)
    for (let i = 0; i < items.length; i++)
      if (root.norm(items[i].id) === n || root.norm(items[i].name) === n) return items[i].key
    return ""
  }

  function keyForAddress(addr) {
    if (!addr) return ""
    const vals = Hyprland.toplevels.values
    for (let i = 0; i < vals.length; i++) {
      const d = vals[i].lastIpcObject
      if (!d || String(d.address) !== String(addr)) continue
      const e = DockService.entryFor(d)
      return e ? "app:" + e.id : "class:" + (d.class || d.initialClass || addr)
    }
    return ""
  }

  // ----------------------------------------------------------- badges
  // How many notifications each app has now, and how many it had when the app
  // was last focused: the difference is what the badge shows.
  readonly property var notifCounts: {
    const out = {}
    if (!root.badgesOn) return out
    const list = NotifService.notifications || []
    for (let i = 0; i < list.length; i++) {
      const n = list[i]
      if (!n) continue
      const k = root.keyForAppName(n.app)
      if (k) out[k] = (out[k] || 0) + 1
    }
    return out
  }
  property var seen: ({})
  // Which apps are in front now. A notification that arrives while its app is
  // already focused is read, not unread: the count it lands on is the count
  // that was seen, so `seen` has to follow the counts for these apps too, not
  // only at the moment they gained focus.
  property var activeKeys: ({})
  function setActive(keys) {
    const next = {}
    for (let i = 0; i < keys.length; i++) next[keys[i]] = true
    root.activeKeys = next
    root.refreshActive()
  }
  function refreshActive() {
    let changed = false
    const next = Object.assign({}, root.seen)
    for (const k in root.activeKeys) {
      const c = root.notifCounts[k] || 0
      if (next[k] !== c) { next[k] = c; changed = true }
    }
    if (changed) root.seen = next
  }
  onNotifCountsChanged: root.refreshActive()

  // Unity's own count, when the app publishes one, beats ours: it is what the
  // app itself calls unread (Thunderbird's inbox, Telegram's chats).
  readonly property var badgeCounts: {
    const out = {}
    if (!root.badgesOn) return out
    const counts = root.notifCounts
    for (const k in counts) {
      const unread = counts[k] - Math.min(root.seen[k] || 0, counts[k])
      if (unread > 0) out[k] = unread
    }
    for (const k in root.unity) {
      const u = root.unity[k]
      if (!u || !u.countVisible) continue
      if (u.count > 0) out[k] = u.count
      else delete out[k]
    }
    return out
  }
  function badgeFor(key) {
    if (!root.badgesOn || !key) return 0
    return root.badgeCounts[key] || 0
  }

  // --------------------------------------------------------- progress
  function progressFor(key) {
    if (!root.progressOn || !key) return -1
    const u = root.unity[key]
    if (!u || !u.progressVisible) return -1
    return Math.max(0, Math.min(1, Number(u.progress) || 0))
  }

  // ----------------------------------------------------------- urgent
  // key -> when it stops. A window's urgent flag has no "false" event in
  // Hyprland worth waiting for, so it fades on its own; focusing clears it.
  property var urgentKeys: ({})
  function markUrgent(key, ms) {
    if (!root.urgentOn || !key) return
    const next = Object.assign({}, root.urgentKeys)
    next[key] = Date.now() + (ms || 8000)
    root.urgentKeys = next
    prune.restart()
  }
  function clearUrgent(key) {
    if (!key || !(key in root.urgentKeys)) return
    const next = Object.assign({}, root.urgentKeys)
    delete next[key]
    root.urgentKeys = next
  }
  function urgentFor(key) {
    return root.urgentOn && !!key && (key in root.urgentKeys)
  }
  property Timer prune: Timer {
    interval: 1000
    repeat: true
    running: Object.keys(root.urgentKeys).length > 0
    onTriggered: {
      const now = Date.now(), next = {}
      let changed = false
      for (const k in root.urgentKeys) {
        if (root.urgentKeys[k] > now) next[k] = root.urgentKeys[k]
        else changed = true
      }
      if (changed) root.urgentKeys = next
    }
  }

  // Critical notifications are the other bearer of "this wants you": Omarchy
  // keeps them until dismissed, so only a new one wiggles its app.
  property var knownIds: ({})
  function scanCritical() {
    const list = NotifService.notifications || [], ids = {}
    for (let i = 0; i < list.length; i++) {
      const n = list[i]
      if (!n) continue
      ids[String(n.id)] = true
      if (Number(n.urgency) === 2 && !root.knownIds[String(n.id)]) {
        const k = root.keyForAppName(n.app)
        if (k) root.markUrgent(k, 8000)
      }
    }
    root.knownIds = ids
  }
  property Connections notifWatch: Connections {
    target: NotifService
    function onNotificationsChanged() { root.scanCritical() }
  }

  // Hyprland: `urgent` carries the window address.
  property Connections hyprWatch: Connections {
    target: Hyprland
    function onRawEvent(e) {
      if (e.name !== "urgent") return
      const k = root.keyForAddress(String(e.data || "").trim())
      if (k) root.markUrgent(k, 8000)
    }
  }

  // ------------------------------------------------------ Unity input
  // key -> { count, countVisible, progress, progressVisible }
  property var unity: ({})
  property string unityId: ""
  property string unityField: ""
  property var unityProps: null

  function readUnityLine(raw) {
    const line = String(raw || "")
    if (line.indexOf("interface=com.canonical.Unity.LauncherEntry") >= 0
        && line.indexOf("member=Update") >= 0) {
      root.flushUnity()
      root.unityProps = ({})
      root.unityId = ""
      root.unityField = ""
      return
    }
    if (line.startsWith("signal ") || line.startsWith("method ")
        || line.startsWith("error ")) {
      root.flushUnity()
      root.unityProps = null
      return
    }
    if (!root.unityProps) return
    const s = line.trim()
    // a{sv} ends the block: dbus-monitor writes the closing bracket last and
    // then nothing, so waiting for the next signal would hold the values back
    // until the app speaks again.
    if (s === "]") { root.flushUnity(); return }
    if (s.indexOf('string "application://') === 0) {
      root.unityId = s.slice('string "application://'.length).replace(/"$/, "")
      return
    }
    if (s.indexOf('string "') === 0) {
      root.unityField = s.slice(8, -1)
      return
    }
    if (s.indexOf("variant ") !== 0) return
    // "double 0.42" | "boolean true" | 'string "x"'
    const rest = s.slice(8).trim(), sp = rest.indexOf(" ")
    if (sp < 0) return
    const type = rest.slice(0, sp)
    let value = rest.slice(sp + 1).trim()
    if (type === "boolean") value = value === "true"
    else if (type === "string") value = value.replace(/^"|"$/g, "")
    else if (type !== "double") value = Number(value)
    else value = Number(value)
    if (root.unityField) root.unityProps[root.unityField] = value
  }

  function flushUnity() {
    const id = root.unityId, props = root.unityProps
    root.unityProps = null
    root.unityId = ""
    root.unityField = ""
    if (!id || !props) return
    const key = root.keyForDesktopId(id)
    if (!key) return
    const next = Object.assign({}, root.unity)
    const cur = Object.assign({}, next[key] || {})
    if ("progress" in props) cur.progress = Math.max(0, Math.min(1, Number(props.progress) || 0))
    if ("progress-visible" in props) cur.progressVisible = !!props["progress-visible"]
    if ("count" in props) cur.count = Math.max(0, Math.round(Number(props.count) || 0))
    if ("count-visible" in props) cur.countVisible = !!props["count-visible"]
    next[key] = cur
    root.unity = next
    if ("urgent" in props) {
      if (props.urgent) root.markUrgent(key, 8000)
      else root.clearUrgent(key)
    }
  }

  // dbus-monitor prints one signal as a header line plus indented lines; the
  // filter keeps it to this interface, so the stream is quiet until an app
  // says something. stdbuf matters: into a pipe, stdio block-buffers, and the
  // bars would arrive only after a few kilobytes of them.
  property Process unityWatch: Process {
    command: ["stdbuf", "-oL", "dbus-monitor", "--session", "interface='com.canonical.Unity.LauncherEntry'"]
    stdout: SplitParser { onRead: line => root.readUnityLine(line) }
    onExited: root.restartWatch.restart()
  }
  property Timer restartWatch: Timer {
    interval: 3000
    onTriggered: if (root.watching) root.unityWatch.running = true
  }
  function watch(on) {
    if (on) { if (!root.unityWatch.running) root.unityWatch.running = true }
    else if (root.unityWatch.running) root.unityWatch.running = false
  }
  Component.onCompleted: root.watch(root.watching)
  onWatchingChanged: root.watch(root.watching)

  // A window of an app that just opened or closed changes what "the dock" is;
  // the seen map is pruned to the counts so a badge cannot come back.
  property Connections itemsWatch: Connections {
    target: DockService
    function onItemsChanged() { root.pruneSeen() }
  }
  function pruneSeen() {
    const counts = root.notifCounts
    let changed = false
    const next = {}
    for (const k in root.seen) {
      const c = counts[k] || 0
      next[k] = Math.min(root.seen[k], c)
      if (next[k] !== root.seen[k]) changed = true
    }
    if (changed) root.seen = next
  }
}
