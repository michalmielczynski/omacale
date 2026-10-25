import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../.."

// Lights (IKEA Dirigera), natively: melon.lights' helper driven from an Omacale
// dashboard card. Rooms come from the hub's own room assignment; a room switch
// sets every light in it, a room slider sets its level, and "Zgasić" clears the
// lot with one button. Per-light colour temperature is left to the hub's own app.
Item {
  id: root

  property bool active: false
  readonly property string helper: Quickshell.env("HOME")
    + "/.config/omarchy/plugins/melon.lights/dirigera.py"

  property var lights: []
  property bool loading: false
  property bool reachable: true
  property string error: ""

  readonly property int total: lights.length
  readonly property int onCount: {
    let n = 0
    for (let i = 0; i < lights.length; i++) if (lights[i].isOn) n++
    return n
  }
  readonly property var rooms: {
    const out = []
    for (let i = 0; i < lights.length; i++) {
      const l = lights[i]
      const name = (l.room && String(l.room).length) ? String(l.room) : "Inne"
      let e = null
      for (let j = 0; j < out.length; j++) if (out[j].name === name) { e = out[j]; break }
      if (!e) { e = { name: name, total: 0, on: 0, ids: [] }; out.push(e) }
      e.total++
      if (l.isOn) e.on++
      e.ids.push(l.id)
    }
    out.sort((a, b) => a.name.localeCompare(b.name))
    return out
  }
  // Every light's level (a lamp that reports no level counts as full), so a
  // room slider starts where the room actually is.
  readonly property var levels: {
    const map = {}
    for (let i = 0; i < lights.length; i++) {
      const l = lights[i]
      map[l.id] = (l.level === undefined || l.level === null) ? 100 : Number(l.level)
    }
    return map
  }
  function idsLevel(ids) {
    if (!ids.length) return 0
    let sum = 0
    for (let i = 0; i < ids.length; i++) sum += root.levels[ids[i]] !== undefined ? root.levels[ids[i]] : 100
    return Math.round(sum / ids.length)
  }
  readonly property int masterLevel: root.idsLevel(root.lights.map(l => l.id))

  // A drag must not fire a request per pixel nor one per light: the level is
  // held per target and sent once the hand stops.
  property var draft: ({})
  Timer {
    id: levelTimer
    interval: 500
    onTriggered: {
      const d = root.draft
      root.draft = ({})
      for (const key in d) {
        const e = d[key]
        for (let i = 0; i < e.ids.length; i++)
          Quickshell.execDetached(["/usr/bin/timeout", "12", "python3", "-B", root.helper, "set", String(e.ids[i]), JSON.stringify({ lightLevel: e.level })])
      }
      refreshTimer.restart()
    }
  }
  function setLevel(ids, level) {
    const lvl = Math.max(1, Math.min(100, Math.round(level)))
    const key = ids.join(",")
    const d = Object.assign({}, root.draft)
    d[key] = { ids: ids, level: lvl }
    root.draft = d
    // Optimistic, like the plugin: the hub answers in its own time.
    const next = Array.from(root.lights)
    for (let i = 0; i < next.length; i++)
      if (ids.indexOf(next[i].id) >= 0) next[i] = Object.assign({}, next[i], { isOn: true, level: lvl })
    root.lights = next
    levelTimer.restart()
  }

  // The bridge/hub can take half a minute to time out; the card should not sit
  // in "loading" for that long.
  Timer {
    id: watchdog
    interval: 15000
    onTriggered: {
      if (!root.loading) return
      root.loading = false
      watchdog.stop()
      root.reachable = false
      root.error = "timeout"
    }
  }

  function poll() {
    if (listProc.running) return
    root.loading = true
    watchdog.restart()
    listProc.running = true
  }
  function setIds(ids, on) {
    const attrs = JSON.stringify({ isOn: on })
    for (let i = 0; i < ids.length; i++)
      Quickshell.execDetached(["/usr/bin/timeout", "12", "python3", "-B", root.helper, "set", String(ids[i]), attrs])
    // Optimistic, like the plugin: the hub answers in its own time.
    const next = Array.from(root.lights)
    for (let i = 0; i < next.length; i++) if (ids.indexOf(next[i].id) >= 0) next[i] = Object.assign({}, next[i], { isOn: on })
    root.lights = next
    refreshTimer.restart()
  }
  function allOff() {
    const ids = []
    for (let i = 0; i < lights.length; i++) if (lights[i].isOn) ids.push(lights[i].id)
    if (ids.length) setIds(ids, false)
  }

  Timer {
    interval: 15000
    repeat: true
    running: root.active
    triggeredOnStart: true
    onTriggered: root.poll()
  }
  Timer { id: refreshTimer; interval: 1500; onTriggered: root.poll() }
  Process {
    id: listProc
    command: ["/usr/bin/timeout", "12", "python3", "-B", root.helper, "devices"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        const t = String(text).trim()
        let parsed = null
        try { parsed = JSON.parse(t) } catch (e) { parsed = null }
        if (Array.isArray(parsed)) {
          root.lights = parsed
          root.reachable = true
          root.error = ""
        } else {
          // The helper reports failures on stderr and prints nothing on stdout.
          root.reachable = false
          if (t) root.error = t
        }
        root.loading = false
        watchdog.stop()
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: { const t = String(text).trim(); if (t) root.error = t }
    }
    onExited: { root.loading = false; watchdog.stop() }
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Tk.spacing.small

    RowLayout {
      Layout.fillWidth: true
      spacing: Tk.spacing.small
      MIcon { text: "lightbulb"; size: Tk.iconSize.large; color: root.onCount > 0 ? Colours.m3primary : Colours.m3secondary }
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        MText { text: "Oświetlenie"; font.pointSize: Tk.title.small; weight: Font.Medium }
        MText {
          text: !root.reachable
            ? (root.loading ? "łączę się z hubem…" : "hub nieosiągalny")
            : root.total === 0 ? "brak lamp" : root.onCount + " z " + root.total + " włączonych"
          color: Colours.m3onSurfaceVariant
          font.pointSize: Tk.body.small
          elide: Text.ElideRight
          Layout.fillWidth: true
        }
      }
      IconTextButton {
        icon: "lightbulb_off"
        text: "Zgasić"
        type: "tonal"
        enabled: root.reachable && root.onCount > 0
        opacity: enabled ? 1 : 0.5
        onClicked: root.allOff()
      }
    }

    // ---- master level: every lamp at once ---------------------------------
    RowLayout {
      Layout.fillWidth: true
      Layout.topMargin: Tk.spacing.extraSmall
      spacing: Tk.spacing.small
      visible: root.reachable && root.total > 0
      MIcon { text: "brightness_6"; size: Tk.iconSize.small; color: Colours.m3onSurfaceVariant }
      MSlider {
        Layout.fillWidth: true
        implicitHeight: Tk.padding.large
        value: root.masterLevel / 100
        onMoved: v => root.setLevel(root.lights.map(l => l.id), v * 100)
      }
      MText {
        Layout.preferredWidth: Tk.px(44)
        horizontalAlignment: Text.AlignRight
        text: root.masterLevel + "%"
        font.pointSize: Tk.body.small
        color: Colours.m3onSurface
      }
    }

    // The hub's own room list can be long (ten rooms here), so it scrolls inside
    // the card instead of stretching it: the tab has a fixed height to fit.
    MListView {
      id: roomList
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.rightMargin: -Tk.spacing.small
      visible: root.reachable
      clip: true
      spacing: Tk.spacing.extraSmall
      ScrollBar.vertical: MScrollBar { flickable: roomList }
      model: root.rooms
      delegate: RowLayout {
        id: roomRow
        required property var modelData
        width: roomList.width
        spacing: Tk.spacing.small
        MText {
          Layout.fillWidth: true
          text: modelData.name
          font.pointSize: Tk.body.medium
          color: modelData.on > 0 ? Colours.m3onSurface : Colours.m3onSurfaceVariant
          elide: Text.ElideRight
        }
        MSlider {
          Layout.preferredWidth: Tk.px(110)
          implicitHeight: Tk.padding.large
          value: root.idsLevel(modelData.ids) / 100
          onMoved: v => root.setLevel(modelData.ids, v * 100)
        }
        MText {
          Layout.preferredWidth: Tk.px(34)
          horizontalAlignment: Text.AlignRight
          text: modelData.on + "/" + modelData.total
          font.pointSize: Tk.label.small
          color: Colours.m3onSurfaceVariant
        }
        MSwitch {
          checked: modelData.on === modelData.total && modelData.total > 0
          onToggled: root.setIds(modelData.ids, checked)
        }
      }
    }

    Item { Layout.fillHeight: true }
  }
}
