import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import "../.."

// Quick toggles card (Caelestia utilities/cards/Toggles.qml): a title and one
// or two ButtonRows of round icon buttons that morph to a squircle when on and
// bulge when pressed. Which buttons show comes from Settings › Utilities, like
// Caelestia's `utilities.quickToggles`; more than six wrap onto a second row.
// Caelestia's VPN toggle is left out: Omarchy has no VPN provider for it.
GlassCard {
  id: root

  property var host
  property var scope

  // services/NightLight.qml reads Omarchy's own status; the state file this
  // used to probe is gone from current Omarchy, so it always showed off.
  readonly property bool nightlightOn: NightLight.on

  readonly property var micSrc: Pipewire.defaultAudioSource
  readonly property bool micOn: micSrc && micSrc.audio ? !micSrc.audio.muted : true

  readonly property var all: [
    { id: "wifi", icon: "wifi", toggle: true },
    { id: "bluetooth", icon: "bluetooth", toggle: true },
    { id: "mic", icon: "mic", toggle: true },
    { id: "settings", icon: "settings", toggle: false },
    { id: "gameMode", icon: "gamepad", toggle: true },
    { id: "dnd", icon: "notifications_off", toggle: true },
    { id: "nightlight", icon: "nightlight", toggle: true },
    // melon: WWAN: radio modemu komórkowego. Bez radia kafelek znika.
    { id: "wwan", icon: "signal_cellular_alt", toggle: true }
  ]
  // Only changes when the settings do, never when a toggle's state flips, so
  // the Repeater keeps its buttons mid-press.
  readonly property var toggles: {
    const on = Config.o.utilities.toggles
    return all.filter(t =>
      (!on || on[t.id] !== false) && (t.id !== "wwan" || root.wwanPresent))
  }
  readonly property int splitIndex: Math.ceil(toggles.length / 2)
  readonly property bool needExtraRow: toggles.length > 6

  function isOn(id) {
    switch (id) {
      case "wifi": return NetService.wifiEnabled
      case "bluetooth": return BtService.enabled
      case "mic": return micOn
      case "gameMode": return GameMode.enabled
      case "dnd": return NotifService.dnd
      case "nightlight": return nightlightOn
      case "wwan": return root.wwanOn
    }
    return false
  }

  function activate(id) {
    if (id === "wifi") NetService.setWifiEnabled(!NetService.wifiEnabled)
    else if (id === "bluetooth") BtService.setEnabled(!BtService.enabled)
    else if (id === "mic") {
      if (micSrc && micSrc.audio) micSrc.audio.muted = !micSrc.audio.muted
      else Sys.run("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle")
    }
    else if (id === "settings") openSettings("")
    else if (id === "gameMode") GameMode.toggle()
    else if (id === "dnd") NotifService.toggleDnd()
    else if (id === "nightlight") NightLight.set(!NightLight.on)
    else if (id === "wwan") root.toggleWwan()
  }

  // ------------------------------------------------------------ melon: WWAN
  // Stan bierze z `wwan-status` (jedna linia: `<stan> key=value …`), a klik
  // idzie do `wwan-toggle` — rfkill bez sudo, dopiero przy zablokowanym
  // firmware Quectla MBIM. Świadomie bez `mmcli --disable`: ten modem
  // zatrzaskuje radio w firmware i wyjścia z tego nie ma bez roota.
  property string wwanBin: (Quickshell.env("HOME") || "") + "/.local/bin"
  property bool wwanOn: false
  property bool wwanPresent: false
  property bool wwanPending: false          // kliknięte, modem jeszcze nie nadąża
  property int wwanTicks: 0

  function wwanApply(line) {
    const parts = (line || "").trim().split(/\s+/)
    const kw = parts[0] || ""
    const rf = (parts.find(p => p.indexOf("rfkill=") === 0) || "").split("=")[1]
    root.wwanPresent = kw !== "absent"
    // Kafelek pokazuje radio (rfkill), nie to, czy modem już się zarejestrował:
    // zapala się od ręki, a `waiting` tylko przedłuża doganianie stanu.
    root.wwanOn = rf ? (rf === "no" || rf === "unblocked")
                     : (kw === "on" || kw === "waiting" || kw === "broken")
    if (kw === "on" || kw === "off") root.wwanPending = false
  }

  function toggleWwan() {
    if (root.wwanPending) return
    root.wwanPending = true
    root.wwanTicks = 12                     // ~18 s doganiania: modem wstaje wolno
    wwanSettle.restart()
    Sys.run(root.wwanBin + "/wwan-toggle toggle")
  }

  property Process wwanStatus: Process {
    command: [root.wwanBin + "/wwan-status"]
    stdout: StdioCollector { onStreamFinished: root.wwanApply(text) }
  }

  // Pyta tylko przy otwartej szufladzie utility — zamknięta nie generuje
  // niczyjego ruchu.
  property Timer wwanPoll: Timer {
    interval: 5000
    repeat: true
    running: root.scope ? root.scope.utilities : true
    triggeredOnStart: true
    onTriggered: root.wwanStatus.running = true
  }
  property Timer wwanSettle: Timer {
    interval: 1500
    repeat: true
    onTriggered: {
      if (root.wwanTicks-- <= 0) { stop(); return }
      root.wwanStatus.running = true
    }
  }

  // Caelestia closes the utilities drawer and opens its settings window;
  // `page` opens it on one page (right-click on Wi-Fi / Bluetooth).
  function openSettings(page) {
    if (scope) { scope.utilities = false; scope.sidebar = false }
    if (host) host.toggle("settings", page)
  }
  readonly property var settingsPages: ({ wifi: "network", bluetooth: "bluetooth", wwan: "network" })


  implicitHeight: layout.implicitHeight + Tk.padding.extraLargeIncreased
  radius: Tk.rounding.large
  fill: Colours.m3surfaceContainer

  ColumnLayout {
    id: layout
    anchors.fill: parent
    anchors.margins: Tk.padding.large
    spacing: Tk.spacing.medium

    MText {
      text: "Quick toggles"
      font.pointSize: Tk.body.medium
    }

    ToggleRow { model: root.needExtraRow ? root.toggles.slice(0, root.splitIndex) : root.toggles }
    ToggleRow { visible: root.needExtraRow; model: root.needExtraRow ? root.toggles.slice(root.splitIndex) : [] }
  }

  component ToggleRow: ButtonRow {
    property alias model: repeater.model
    Layout.fillWidth: true
    spacing: Tk.spacing.small

    Repeater {
      id: repeater
      delegate: IconButton {
        required property var modelData
        // Caelestia keeps "mic": a muted mic is the toggle's unfilled off state.
        icon: modelData.icon
        checked: root.isOn(modelData.id)
        toggle: modelData.toggle
        fillWidth: true
        shapeMorph: true
        round: true
        // melon: wlaczone kafle byly kwadratami, wylaczone kolami (radius
        // IconButton: on ? medium : height/2). Jeden ksztalt dla obu stanow,
        // morfniecia przy nacisnieciu zostaje.
        radius: stateLayer.pressed ? Tk.rounding.small : Tk.rounding.medium
        inactiveColour: Colours.layer(Colours.palette.m3surfaceContainerHighest, 2)
        inactiveOnColour: Colours.m3onSurfaceVariant
        onClicked: root.activate(modelData.id)

        // Right-click jumps to the matching settings page. Only the right
        // button is taken, so left clicks still reach the button below.
        MouseArea {
          anchors.fill: parent
          enabled: !!root.settingsPages[parent.modelData.id]
          acceptedButtons: Qt.RightButton
          onClicked: root.openSettings(root.settingsPages[parent.modelData.id])
        }
      }
    }
  }
}
