import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../.."

// Ventilation (Thessla Green AirPack 500h), natively: melon.rekuperacja's own
// helper -- the HTTP bridge on the Raspberry Pi -- driven from an Omacale
// dashboard card instead of that plugin's bar widget. The plugin pill is off, so
// nothing of the plugin draws in the bar any more.
//
// Reading is cheap-ish (the bridge answers from its cache with `--fast`), so it
// polls every 20 s and only while the tab is on screen. Every write is followed
// by a re-read, as the plugin's panel did. The controls mirror that panel:
// Start/Stop, mode (auto/manual), season, the airflow setpoint and the bypass.
Item {
  id: root

  property bool active: false
  readonly property string helper: Quickshell.env("HOME")
    + "/.config/omarchy/plugins/melon.rekuperacja/rekuperacja.py"

  property var s: ({})
  property bool loading: false
  property string error: ""

  readonly property bool online: s.online === true
  readonly property bool powerOn: online && s.on === true
  readonly property var fans: s.fans !== undefined ? s.fans : ({})
  readonly property var temps: s.temperatures !== undefined ? s.temperatures : ({})
  readonly property var alarms: s.alarms !== undefined ? s.alarms : ({})
  readonly property var bypass: s.bypass !== undefined ? s.bypass : ({})
  readonly property int supplyFlow: fans.supply_percent !== undefined ? fans.supply_percent : 0
  readonly property int exhaustFlow: fans.exhaust_percent !== undefined ? fans.exhaust_percent : 0
  // The setpoint the bridge reports (what the unit was told), falling back to the
  // measured flow on a bridge that does not report one.
  readonly property int setFlow: fans.set_supply_flow !== undefined && fans.set_supply_flow > 0
    ? fans.set_supply_flow : supplyFlow
  readonly property string mode: s.mode !== undefined && s.mode !== null ? String(s.mode) : ""
  readonly property string season: s.season !== undefined && s.season !== null ? String(s.season) : ""
  readonly property string modeText: {
    const m = mode === "auto" ? "automatyczny" : mode === "manual" ? "manualny" : mode === "temporary" ? "tymczasowy" : mode
    const se = season === "summer" ? "lato" : season === "winter" ? "zima" : season
    const parts = []
    if (m) parts.push(m)
    if (se) parts.push(se)
    return parts.join(" · ")
  }
  // Nothing but the bridge's own keys: an alarm is a true flag in `alarms`.
  readonly property string alarmText: {
    if (s.alarm === true) return "Alarm"
    const keys = Object.keys(alarms)
    for (let i = 0; i < keys.length; i++) if (alarms[keys[i]] === true) return String(keys[i])
    return ""
  }
  readonly property bool bypassOn: bypass.enabled === true
  function temp(v) { return (v === undefined || v === null || isNaN(v)) ? "—" : (Math.round(v * 10) / 10) + "°" }

  // ---- writes -------------------------------------------------------------
  // One command at a time: the bridge holds a single RS485 session, and the
  // plugin's panel serialised its writes the same way.
  function write(args) {
    if (writeProc.running) { pendingWrite = args; pendingTimer.restart(); return }
    writeProc.command = ["/usr/bin/timeout", "25", "python3", "-B", root.helper].concat(args)
    writeProc.running = true
  }
  property var pendingWrite: null
  Timer { id: pendingTimer; interval: 400; onTriggered: if (root.pendingWrite) root.write(root.pendingWrite) }

  function power(on) { write([on ? "on" : "off"]) }
  function setMode(m) { write(["mode", String(m)]) }
  function setSeason(se) { write(["season", String(se)]) }
  function setBypass(on) { write(["bypass", on ? "on" : "off"]) }
  // Dragging a slider must not fire a request per pixel: the draft is held and
  // sent once the hand stops (the optimistic value shows meanwhile).
  property int flowDraft: -1
  readonly property int flowShown: flowDraft >= 0 ? flowDraft : setFlow
  Timer { id: flowTimer; interval: 500; onTriggered: { root.flowDraft = -1; root.write(["airflow", String(root.flowShown), "--manual"]) } }
  function setFlow(pct) {
    root.flowDraft = Math.max(0, Math.min(100, Math.round(pct)))
    flowTimer.restart()
  }

  // The bridge can take half a minute to time out; the card should not sit in
  // "loading" for that long.
  // The bridge serialises one RS485 session, and while the phone app holds it a
  // status call can take ~20 s (measured 2026-10-01). `timeout` in the command is
  // what makes the card recover: it ends the call, onExited clears `loading`, and
  // the next tick polls again -- without it a hung call blocked `poll()` for good.
  Timer {
    id: watchdog
    interval: 30000
    onTriggered: {
      if (!root.loading) return
      root.loading = false
      watchdog.stop()
      // No answer in time: drop the stale reading, the card then reads offline.
      root.s = ({})
      root.error = "timeout"
    }
  }

  function poll() {
    if (stateProc.running) return
    root.loading = true
    watchdog.restart()
    stateProc.running = true
  }

  // A minute, not the 20 s the card started with: each status call holds the
  // bridge's single RS485 session for up to ~20 s while the phone app is also
  // asking, so a fast poll only made the contention worse. Ventilation state does
  // not change that quickly.
  Timer {
    interval: 60000
    repeat: true
    running: root.active
    triggeredOnStart: true
    onTriggered: root.poll()
  }
  Process {
    id: stateProc
    command: ["/usr/bin/timeout", "25", "python3", "-B", root.helper, "status", "--fast"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        const t = String(text).trim()
        try { root.s = JSON.parse(t) } catch (e) { root.s = ({}) }
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
  Process { id: writeProc; onExited: root.poll() }

  ColumnLayout {
    anchors.fill: parent
    spacing: Tk.spacing.small

    RowLayout {
      Layout.fillWidth: true
      spacing: Tk.spacing.small
      MIcon {
        text: "air"
        size: Tk.iconSize.large
        color: root.alarmText !== "" ? Colours.m3error : Colours.m3secondary
      }
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        MText { text: "Rekuperacja"; font.pointSize: Tk.title.small; weight: Font.Medium }
        MText {
          text: root.online
            ? (root.powerOn ? (root.modeText || "pracuje") : "zatrzymana" + (root.modeText ? " · " + root.modeText : ""))
            : (root.loading ? "łączę się z mostkiem…" : "brak łączności z mostkiem")
          color: root.alarmText !== "" ? Colours.m3error : Colours.m3onSurfaceVariant
          font.pointSize: Tk.body.small
          elide: Text.ElideRight
          Layout.fillWidth: true
        }
      }
      IconTextButton {
        icon: root.powerOn ? "power_settings_new" : "power_off"
        text: root.powerOn ? "Stop" : "Start"
        type: "tonal"
        enabled: root.online
        opacity: enabled ? 1 : 0.5
        onClicked: root.power(!root.powerOn)
      }
    }

    RowLayout {
      Layout.fillWidth: true
      Layout.topMargin: Tk.spacing.small
      spacing: Tk.spacing.largeIncreased
      visible: root.online
      HomeValue { label: "nawiew"; value: root.supplyFlow + "%" }
      HomeValue { label: "wyrzut"; value: root.exhaustFlow + "%" }
      Item { Layout.fillWidth: true }
      HomeValue { label: "zewnątrz"; value: root.temp(root.temps.outside) }
      HomeValue { label: "nawiew"; value: root.temp(root.temps.supply) }
      HomeValue { label: "wywiew"; value: root.temp(root.temps.exhaust) }
    }

    // ---- controls: mode, season, the airflow setpoint, the bypass ----------
    RowLayout {
      Layout.fillWidth: true
      Layout.topMargin: Tk.spacing.small
      spacing: Tk.spacing.small
      visible: root.online
      SplitSelect {
        filled: true
        horizontalPadding: Tk.padding.medium
        menuOnTop: true
        enabled: root.online
        current: root.mode === "temporary" ? "manual" : root.mode
        items: [
          { icon: "autorenew", text: "automatyczny", value: "auto" },
          { icon: "tune", text: "manualny", value: "manual" }
        ]
        onSelected: v => root.setMode(v)
      }
      SplitSelect {
        filled: true
        horizontalPadding: Tk.padding.medium
        menuOnTop: true
        enabled: root.online
        current: root.season
        items: [
          { icon: "sunny", text: "lato", value: "summer" },
          { icon: "ac_unit", text: "zima", value: "winter" }
        ]
        onSelected: v => root.setSeason(v)
      }
      Toggle {
        label: "bypass"
        enabled: root.online
        checked: root.bypassOn
        onToggled: c => root.setBypass(c)
      }
      Item { Layout.fillWidth: true }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Tk.spacing.small
      visible: root.online
      MIcon { text: "mode_fan"; size: Tk.iconSize.small; color: Colours.m3onSurfaceVariant }
      MText {
        text: "przepływ"
        font.pointSize: Tk.body.small
        color: Colours.m3onSurfaceVariant
      }
      MSlider {
        Layout.fillWidth: true
        implicitHeight: Tk.padding.large
        enabled: root.online
        // The setpoint the bridge reports, or the last drag while it is open.
        value: root.flowShown / 100
        onMoved: v => root.setFlow(v * 100)
      }
      MText {
        Layout.preferredWidth: Tk.px(44)
        horizontalAlignment: Text.AlignRight
        text: root.flowShown + "%"
        font.pointSize: Tk.body.small
        color: Colours.m3onSurface
      }
    }

    RowLayout {
      Layout.fillWidth: true
      visible: root.alarmText !== ""
      spacing: Tk.spacing.extraSmall
      MIcon { text: "warning"; size: Tk.iconSize.medium; color: Colours.m3error }
      MText { text: root.alarmText; color: Colours.m3error; font.pointSize: Tk.body.small }
      Item { Layout.fillWidth: true }
    }

    Item { Layout.fillHeight: true }
  }
}
