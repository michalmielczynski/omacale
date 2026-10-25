import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../.."

// Sony WF-1000XM5, natively: melon.sony's helper driven from an Omacale
// dashboard card. The helper keeps one long-lived `serve` process owning the
// BlueZ session and a unix socket; this card is a *client* of that socket
// (`ctl state`, `ctl anc …`), so it never starts a second session. If no
// helper is running at all -- the plugin's own widget is the usual one -- it
// starts one and re-reads.
Item {
  id: root

  property bool active: false
  readonly property string dir: Quickshell.env("HOME") + "/.config/omarchy/plugins/melon.sony"
  readonly property string helper: dir + "/sony-helper.py"

  property var s: ({})
  property bool loading: false
  property string error: ""
  // `ctl` talks to the helper's unix socket; no socket means no helper running.
  property bool helperDown: false

  readonly property var buds: s.buds !== undefined ? s.buds : ({})
  readonly property var anc: s.anc !== undefined ? s.anc : ({})
  readonly property var eq: s.eq !== undefined ? s.eq : ({})
  readonly property string link: s.link !== undefined ? String(s.link) : "idle"
  readonly property bool online: link === "ready"
  readonly property bool connected: s.connected === true
  readonly property string deviceName: s.name !== undefined && String(s.name).length ? String(s.name) : "Sony"
  readonly property string reason: s.reason !== undefined ? String(s.reason) : ""
  readonly property string ancMode: anc.mode !== undefined ? String(anc.mode) : "off"
  function level(v) { return (v === undefined || v === null) ? "—" : String(v) + "%" }
  readonly property string seen: {
    if (root.helperDown) return "helper nie działa"
    if (root.connected && root.online) return "połączone"
    if (root.reason.length) return root.reason
    if (root.online) return "gotowe"
    return root.loading ? "odczyt…" : "offline"
  }

  function poll() {
    if (ctlProc.running) return
    root.loading = true
    ctlProc.command = ["/usr/bin/timeout", "15", "python3", "-B", root.helper, "ctl", "state"]
    ctlProc.running = true
  }
  // The melon.sony plugin is disabled, so nothing else spawns the helper any
  // more: the card starts it once when it finds no socket (the hidden bar widget
  // used to do this). The helper itself hands the control session back to the
  // phone, so having it running is what the plugin always did; the Start button
  // stays as the manual retry.
  property bool autoStarted: false
  onHelperDownChanged: {
    if (active && helperDown && !autoStarted) {
      autoStarted = true
      serveProc.running = true
      retryTimer.restart()
    }
  }
  onActiveChanged: if (!active) autoStarted = false
  function setAnc(mode) {
    if (actionProc.running || root.ancMode === mode) return
    actionProc.command = ["/usr/bin/timeout", "15", "python3", "-B", root.helper, "ctl", "anc", mode]
    actionProc.running = true
  }

  Timer {
    interval: 10000
    repeat: true
    running: root.active
    triggeredOnStart: true
    onTriggered: root.poll()
  }
  Timer { id: retryTimer; interval: 1800; onTriggered: root.poll() }
  Process {
    id: ctlProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        const t = String(text).trim()
        let parsed = null
        try { parsed = JSON.parse(t) } catch (e) { parsed = null }
        if (parsed && (parsed.type === "state" || parsed.anc !== undefined)) {
          root.s = parsed
          root.error = ""
        } else if (parsed && parsed.error !== undefined) {
          // No socket: no helper is running. Never start one on our own -- a
          // second `serve` unlinks and recreates the socket under the first,
          // which is how the plugin's own widget and this card would fight.
          // The button below does it once, on purpose.
          root.error = String(parsed.error)
          root.helperDown = true
        }
        root.loading = false
      }
    }
    onExited: root.loading = false
  }
  Process {
    id: actionProc
    onExited: root.poll()
  }
  // Started only from the button below: one helper at a time.
  Process {
    id: serveProc
    running: false
    command: ["python3", "-B", root.helper, "serve"]
    onExited: console.warn("omacale: melon.sony helper exited, code " + exitCode)
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Tk.spacing.small

    RowLayout {
      Layout.fillWidth: true
      spacing: Tk.spacing.small
      MIcon {
        text: "headphones"
        size: Tk.iconSize.large
        color: root.connected ? Colours.m3primary : Colours.m3secondary
      }
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        MText {
          text: root.deviceName
          font.pointSize: Tk.title.small
          weight: Font.Medium
          elide: Text.ElideRight
          Layout.fillWidth: true
        }
        MText {
          text: root.seen
          color: root.connected ? Colours.m3onSurfaceVariant : Colours.m3error
          font.pointSize: Tk.body.small
          elide: Text.ElideRight
          Layout.fillWidth: true
        }
      }
      IconTextButton {
        visible: root.helperDown
        icon: "play_arrow"
        text: "Start"
        type: "tonal"
        onClicked: { root.helperDown = false; serveProc.running = true; retryTimer.restart() }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      Layout.topMargin: Tk.spacing.extraSmall
      spacing: Tk.spacing.largeIncreased
      HomeValue { label: "lewa"; value: root.level(root.buds.left) }
      HomeValue { label: "prawa"; value: root.level(root.buds.right) }
      HomeValue { label: "etui"; value: root.level(root.buds.case) }
      HomeValue { label: "Bluetooth"; value: root.level(root.s.bluez_battery) }
    }

    RowLayout {
      Layout.fillWidth: true
      Layout.topMargin: Tk.spacing.extraSmall
      spacing: Tk.spacing.extraSmall
      visible: root.online
      IconTextButton {
        icon: "noise_control_on"
        text: "ANC"
        type: root.ancMode === "anc" ? "filled" : "text"
        enabled: root.connected
        onClicked: root.setAnc("anc")
      }
      IconTextButton {
        icon: "noise_aware"
        text: "Ambient"
        type: root.ancMode === "ambient" ? "filled" : "text"
        enabled: root.connected
        onClicked: root.setAnc("ambient")
      }
      IconTextButton {
        icon: "noise_control_off"
        text: "Off"
        type: root.ancMode === "off" ? "filled" : "text"
        enabled: root.connected
        onClicked: root.setAnc("off")
      }
      Item { Layout.fillWidth: true }
      MText {
        visible: root.eq.preset !== undefined
        text: "EQ: " + String(root.eq.preset)
        font.pointSize: Tk.label.small
        color: Colours.m3onSurfaceVariant
      }
    }

    Item { Layout.fillHeight: true }
  }

}
