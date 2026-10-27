import QtQuick
import Quickshell.Widgets
import "../.."

// One app in the dock: its icon on a rounded cell, and a dot per open window
// (up to three) on the side facing the dock's edge, the active app's in
// m3primary. No Caelestia original (Caelestia has no dock); the cell is a
// plain icon that gives under a press and springs back.
Item {
  id: root

  // The app (DockService.items entry); set by the dock, which keeps this
  // icon alive across rebuilds of its list.
  property var modelData: ({ windows: [], active: false, icon: "", name: "" })
  property real cell: Tk.px(48)
  property bool full: false
  property string edge: "bottom"
  property bool menuShown: false
  property bool highlighted: false
  property string names: "off"
  property bool previewOpen: false
  // The dock's magnification of this icon; it grows away from the edge.
  property real mag: 1

  signal menuRequested
  signal dismissRequested
  signal hoverChanged(bool hovered)
  // A drag along the dock: how far from where it was pressed.
  signal dragMoved(real offset)
  signal dragEnded(real offset)
  readonly property bool vert: edge === "left" || edge === "right"

  // Press: the icon gives a little under the finger and springs back; no
  // Material ripple. Omacale's own motion is springs and jelly, not circles.
  Spring {
    id: pressSpring
    value: 1
    target: pressArea.pressed ? 0.88 : 1
    stiffness: 520
    damping: 24
  }

  transform: Scale {
    origin.x: root.edge === "left" ? 0 : root.edge === "right" ? root.width : root.width / 2
    origin.y: root.edge === "top" ? 0 : root.edge === "bottom" ? root.height : root.height / 2
    xScale: root.mag * pressSpring.value
    yScale: root.mag * pressSpring.value
  }

  readonly property int dots: Math.min(3, modelData.windows.length)

  implicitWidth: cell
  implicitHeight: names === "always" ? cell + (full ? Tk.px(24) : Tk.px(18)) : cell

  Rectangle {
    id: bg
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: root.cell
    radius: Math.min(width, height) / 2
    // Only the app whose menu is open gets a tile; the active one is told by
    // its dot, so every icon sits on the plate the same way.
    color: root.menuShown ? Colours.m3surfaceContainerHighest : "transparent"
    Behavior on color { CAnim {} }

    MouseArea {
      id: pressArea
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
      cursorShape: dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
      // Pressed and moved past a few px along the dock: a drag, not a click.
      property real startAlong: 0
      property bool dragging: false
      property real lastD: 0
      // The frame's own MouseArea mustn't take the drag over.
      preventStealing: true
      function along(e) { return root.vert ? mapToItem(null, e.x, e.y).y : mapToItem(null, e.x, e.y).x }
      onPressed: e => { startAlong = along(e); dragging = false; lastD = 0 }
      onPositionChanged: e => {
        if (!pressed || !(pressedButtons & Qt.LeftButton)) return
        const d = along(e) - startAlong
        if (!dragging && Math.abs(d) > 8) dragging = true
        if (dragging) { lastD = d; root.dragMoved(d) }
      }
      onReleased: e => { if (dragging) root.dragEnded(along(e) - startAlong) }
      // A grab taken mid-drag still drops where it was.
      onCanceled: { if (dragging) { dragging = false; root.dragEnded(lastD) } }
      onContainsMouseChanged: root.hoverChanged(containsMouse)
      onClicked: e => {
        if (dragging) { dragging = false; return }
        if (e && e.button === Qt.RightButton) root.menuRequested()
        else {
          root.dismissRequested()
          if (e && e.button === Qt.MiddleButton) DockService.launch(root.modelData)
          else DockService.activate(root.modelData)
        }
      }
    }
  }

  // The cell's edge side holds the window dots (dotRoom), so the icon is
  // centred in what is left and the two never touch.
  readonly property real dotRoom: Tk.px(9)
  readonly property real iconSize: Math.round(Math.min(root.cell * (root.full ? 0.66 : 0.78), root.cell - dotRoom * 2 + Tk.px(6)))
  IconImage {
    implicitSize: root.iconSize
    readonly property real away: (root.dotRoom - (root.cell - root.iconSize) / 2) > 0 ? root.dotRoom - (root.cell - root.iconSize) / 2 : 0
    x: Math.round((root.width - width) / 2 + (root.edge === "left" ? away : root.edge === "right" ? -away : 0))
    y: root.full ? Math.round((root.cell - height) / 2)
      : Math.round((root.height - height) / 2 + (root.edge === "top" ? away : root.edge === "bottom" ? -away : 0))
    asynchronous: true
    source: root.modelData.icon
    opacity: pressArea.pressed ? 0.9 : 1
    Behavior on opacity { Anim { type: "fastEffects" } }
  }

  // The window dots, on the edge side of the cell.
  Grid {
    readonly property bool vert: root.edge === "left" || root.edge === "right"
    columns: vert ? 1 : 3
    spacing: Tk.px(3)
    x: root.edge === "left" ? Tk.px(2) : root.edge === "right" ? root.width - width - Tk.px(2) : Math.round((root.width - width) / 2)
    y: root.full ? (root.edge === "top" ? Tk.px(3) : root.cell - height - Tk.px(3))
      : root.edge === "top" ? Tk.px(2) : root.edge === "bottom" ? root.height - height - Tk.px(2) : Math.round((root.height - height) / 2)
    Repeater {
      model: root.dots
      Rectangle {
        width: root.modelData.active && index === 0 ? Tk.px(10) * (parent.vert ? 0.5 : 1) : Tk.px(5)
        height: root.modelData.active && index === 0 ? Tk.px(10) * (parent.vert ? 1 : 0.5) : Tk.px(5)
        radius: Tk.rounding.full
        color: root.modelData.active ? Colours.m3primary : Colours.m3onSurfaceVariant
        Behavior on width { Anim { type: "fastSpatial" } }
        Behavior on height { Anim { type: "fastSpatial" } }
      }
    }
  }

  // The app's name over (or below) the cell, in the cell's own layer: no
  // global hover index to get out of step while the list rebuilds.
  Rectangle {
    id: nameLabel
    enabled: false
    visible: !root.full && root.names === "hover" && (pressArea.containsMouse || root.highlighted)
      && !root.menuShown && !root.previewOpen
    opacity: visible ? 1 : 0
    Behavior on opacity { Anim { type: "fastEffects" } }
    z: 3
    width: nameText.implicitWidth + Tk.padding.medium * 2
    height: nameText.implicitHeight + Tk.padding.small * 2
    radius: Tk.rounding.small
    color: Colours.m3surfaceContainerHigh
    x: Math.round((root.width - width) / 2)
    y: root.edge === "top" ? root.height + Tk.spacing.small : -height - Tk.spacing.small
    MText {
      id: nameText
      anchors.centerIn: parent
      text: root.modelData.name || ""
      font.pointSize: Tk.label.large
      color: Colours.m3onSurface
    }
  }

  // Full size: the name is part of the cell, under the icon, like a launcher
  // tile. Compact keeps the name as a pill on hover.
  MText {
    id: fullName
    visible: root.names === "always"
      || (root.full && root.names === "hover" && (pressArea.containsMouse || root.highlighted))
    width: root.cell
    y: root.cell + (root.full ? Tk.px(4) : Tk.px(2))
    text: root.modelData.name || ""
    horizontalAlignment: Text.AlignHCenter
    elide: Text.ElideRight
    font.pointSize: root.full ? Tk.label.medium : Tk.label.small
    color: root.highlighted ? Colours.m3onSurface : Colours.m3onSurfaceVariant
  }
}
