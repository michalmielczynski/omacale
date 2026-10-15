pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../.."

// Live captions drawn by Omacale itself: one surface on the bottom edge, in the
// shape of the desktop clock (modules/background/Background.qml) — a PanelWindow
// with a namespace, a blur rule written by Bar.applyDesktopBlur, and an exclusive
// zone when the strip is reserved.
//
// Data comes from the caption socket: the ASR pipeline connects to us (it already
// talks the same protocol to the GTK bar in ~/captions/overlay.py), so nothing in
// the transcription changes; a listener is all this needs, and `socat` provides it
// without a line of socket code in QML.
//
// Protocol, the same one the GTK bar speaks:
//   "" or "\x04"      clear
//   "\x02<text>"      unconfirmed draft (the fast model's tail)
//   "\x01<text>"      start a new phrase
//   anything else     append to the current phrase
//
// Drawn with Omacale's colours, so it follows the palette and the UI scale.
Item {
  id: root

  required property var screen
  required property string barPos        // the bar's edge on this screen
  required property real barZone         // its reserved width, for this surface's margin

  readonly property var cfg: Config.o.captions
  readonly property string socket: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/omacale-captions.sock"

  // Roles as in overlay.py: past fades with age, the last completed sentence is
  // brightest, the sentence being built is primary, the draft is a dim primary.
  readonly property color cDone: Colours.m3onSurface
  readonly property color cPast: Colours.m3onSurfaceVariant
  readonly property color cOpen: Colours.m3primary

  property string buf: ""
  property string draft: ""

  function clear(): void { buf = ""; draft = "" }

  function feed(line): void {
    const s = String(line === undefined ? "" : line).replace(/\n+$/, "")
    if (s === "\u0004" || s.trim() === "") { root.clear(); return }
    if (s.startsWith("\u0002")) { root.draft = s.slice(1).trim(); return }
    if (s.startsWith("\u0001")) { root.buf = s.slice(1); root.draft = ""; return }
    let add = s
    if (root.buf !== "" && !/[\s]$/.test(root.buf) && !/^[\s.,?!'’)]/.test(add)) add = " " + add
    root.buf += add
    if (root.buf.length > 400) root.buf = root.buf.slice(-400)
  }

  // Sentences and the tail still being built (the same split the GTK bar does,
  // minus its abbreviation list — a wrong break here only shifts the colour).
  readonly property var parts: {
    const sentences = []
    const re = /[^.!?…]*[.!?…]+["')\]]*\s*/g
    let m, end = 0
    while ((m = re.exec(root.buf)) !== null) {
      if (m.index !== end) break
      sentences.push(m[0])
      end = re.lastIndex
    }
    return { sentences: sentences, tail: root.buf.slice(end) }
  }

  function rgba(c, a): string {
    return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + a.toFixed(2) + ")"
  }
  function esc(t): string {
    return String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }

  readonly property string rich: {
    const p = root.parts
    const n = p.sentences.length
    let out = ""
    for (let i = 0; i < n; i++) {
      const last = i === n - 1
      const col = last ? root.cDone : root.cPast
      const a = last ? 1.0 : Math.max(0.32, 0.72 - 0.06 * (n - 1 - i))
      out += "<span style=\"color:" + root.rgba(col, a) + "\">" + root.esc(p.sentences[i]) + "</span>"
    }
    if (p.tail !== "")
      out += "<span style=\"color:" + root.rgba(root.cOpen, 0.95) + "\">" + root.esc(p.tail) + "</span>"
    if (root.draft !== "")
      out += (out === "" ? "" : " ") + "<span style=\"color:" + root.rgba(root.cOpen, 0.6) + "\">" + root.esc(root.draft) + "</span>"
    return out
  }

  // ---- the socket: the ASR connects to us, socat prints the lines ----
  Process {
    id: reader
    running: root.cfg.enabled
    command: ["socat", "-u", "UNIX-LISTEN:" + root.socket + ",unlink-early,reuseaddr", "-"]
    stdout: SplitParser { onRead: line => root.feed(line) }
    onExited: if (root.cfg.enabled) retry.restart()
  }
  Timer {
    id: retry
    interval: 1000
    onTriggered: reader.running = true
  }

  // ---- the surface ----
  PanelWindow {
    id: win

    screen: root.screen
    color: "transparent"
    visible: root.cfg.enabled
    implicitHeight: Math.round(root.cfg.height)
    exclusionMode: root.cfg.enabled && root.cfg.reserve ? ExclusionMode.Normal : ExclusionMode.Ignore
    exclusiveZone: root.cfg.enabled && root.cfg.reserve ? Math.round(root.cfg.height) : 0
    WlrLayershell.namespace: "omacale-captions"
    // Overlay, not top: a fullscreen video would cover a `top` surface (the same
    // reason the notification toasts live on their own overlay window).
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    anchors { bottom: true; left: true; right: true }
    margins {
      // The compositor places a surface after the bar's left reserve and after the
      // frame's border reserve; the strip should reach the screen edges instead
      // (the same place the GTK bar sat), hence the negative margins.
      left: root.barPos === "left" ? -Math.round(root.barZone) : 0
      right: root.barPos === "right" ? -Math.round(root.barZone) : -Math.round(Tk.border)
      bottom: -Math.round(Tk.border)
    }
    // No input at all: clicks go to the window underneath, as the GTK strip does.
    mask: Region {}

    Rectangle {
      anchors.fill: parent
      color: Colours.m3surfaceContainer
      border.width: 1
      border.color: Colours.m3outlineVariant

      Item {
        id: clip
        anchors.fill: parent
        anchors.leftMargin: Tk.padding.large
        anchors.rightMargin: Tk.padding.large
        clip: true

        MText {
          id: caption
          textFormat: Text.RichText
          text: root.rich
          color: Colours.m3onSurface
          font.pixelSize: Tk.px(Math.round(21 * root.cfg.fontScale))
          anchors.verticalCenter: parent.verticalCenter
          // The newest words stay in view; longer text slides left.
          x: Math.min(0, clip.width - implicitWidth)
          Behavior on x { Anim { type: "spatial" } }
        }
      }
    }
  }
}
