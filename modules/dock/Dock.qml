import QtQuick
import "../.."

// The dock's content: the pinned apps, a divider, then the open apps that
// aren't pinned (DockService.items), in a row on the top or bottom edge or a
// column on the left or right one. A right click opens the app's menu inside
// the dock, on the side away from the edge, so the drawer grows to hold it.
//
// No Caelestia original (Caelestia has no dock). Drawn as a drawer of the
// frame (ScreenScope's r10), in the launcher's tokens.
Item {
  id: root

  property string edge: "bottom"
  // The workspace "Move here" moves windows to (this screen's active one).
  property int workspaceId: 1
  // This screen's Hyprland monitor id, for dock.scope "monitor".
  property int monitorId: -1

  // The pointer is on the dock (its edge strip is the ScreenScope's).
  signal hoverChanged(bool hovered)
  // A menu or the previews keep the drawer out after the pointer leaves.
  signal menuChanged(bool open)
  signal launcherRequested
  signal dismissRequested
  readonly property bool vertical: edge === "left" || edge === "right"
  // Compact is the original pill; full is a dashboard-sized drawer: names
  // under the icons and room for the apps to breathe.
  readonly property bool full: Config.o.dock.size === "full"
  readonly property string names: Config.o.dock.names || "off"
  readonly property real cell: Tk.px(full ? Math.round(Config.o.dock.iconSize * 1.5) : Config.o.dock.iconSize)
  // The icons sit on a plate of their own inside the drawer: with a theme
  // whose surface is the windows' colour (a black one) the drawer alone
  // doesn't show where the dock is. The window dots live in its margin.
  readonly property real platePad: Tk.padding.small
  readonly property real pad: full ? Tk.padding.largeIncreased : Tk.padding.small + platePad
  readonly property real gap: full ? Tk.spacing.medium : Tk.spacing.small
  readonly property real fullMinWidth: Tk.px(560)

  // The app whose menu is open (its key), "" for none.
  property string menuKey: ""
  readonly property var menuApp: {
    if (!menuKey) return null
    const it = root.scoped.find(i => i.key === menuKey)
    return it || null
  }
  readonly property bool menuOpen: menuApp !== null
  onMenuOpenChanged: root.menuChanged(root.menuOpen)
  function closeMenu() { menuKey = ""; previewKey = "" }

  readonly property bool empty: root.entries.length === 0
  readonly property string hoveredName: {
    const e = root.entries[root.hoveredIndex]
    return e && e.kind === "app" ? e.app.name : ""
  }
  // The pointer is anywhere on the dock (icons, menu, previews).
  readonly property bool pointerOn: dockHover.hovered
  // Set by the cell under the pointer; independent of the grid's hover.
  property string hoveredKey: ""
  onHoveredKeyChanged: root.hoverChanged(dockHover.hovered || hoveredKey !== "")

  // ----------------------------------------------------------- previews
  // An open app hovered for a moment shows its windows, live, in the same
  // place the menu opens; they stay while the pointer is anywhere on the
  // dock, and follow it to the next open app it rests on.
  property string previewKey: ""
  readonly property var previewApp: {
    if (!previewKey || menuOpen || dragKey !== "") return null
    const it = root.scoped.find(i => i.key === previewKey)
    return it && it.windows.length ? it : null
  }
  readonly property bool previewOpen: previewApp !== null
  Timer {
    id: previewDwell
    interval: 500
    onTriggered: {
      const e = root.hoveredIndex >= 0 ? root.entries[root.hoveredIndex] : null
      if (e && e.kind === "app" && e.app.windows.length) root.previewKey = e.app.key
    }
  }
  onHoveredIndexChanged: {
    if (!Config.o.dock.previews || hoveredIndex < 0) { previewDwell.stop(); return }
    // Already showing some: the next app's come straight away.
    if (previewOpen) previewDwell.triggered()
    else previewDwell.restart()
  }
  HoverHandler {
    id: dockHover
    onHoveredChanged: root.hoverChanged(hovered)
  }
  Timer {
    id: previewLeave
    interval: Math.max(200, Config.o.dock.hideDelay)
    running: root.previewKey !== "" && !root.pointerOn && root.hoveredKey === "" && !root.menuOpen
    onTriggered: root.previewKey = ""
  }

  // dock.scope: each app with only the windows that count here; an
  // unpinned app left with none is dropped.
  readonly property var scoped: {
    const sc = Config.o.dock.scope
    if (sc !== "monitor" && sc !== "workspace") return DockService.items
    const keep = w => sc === "monitor" ? w.monitor === monitorId : w.workspace === workspaceId
    const out = []
    for (const it of DockService.items) {
      const wins = it.windows.filter(keep)
      if (!wins.length && !it.pinned) continue
      out.push(Object.assign({}, it, { windows: wins, active: wins.some(w => w.address === DockService.activeAddress) }))
    }
    return out
  }
  // Pinned apps, a divider (when both kinds are there), the rest.
  readonly property var entries: {
    const all = root.scoped, out = []
    const pins = all.filter(i => i.pinned), rest = all.filter(i => !i.pinned)
    for (const p of pins) out.push({ kind: "app", app: p })
    if (pins.length && rest.length) out.push({ kind: "divider" })
    for (const r of rest) out.push({ kind: "app", app: r })
    return out
  }

  // ------------------------------------------------------------ magnify
  // Each icon grows with the pointer's nearness along the dock (a cosine
  // over 2.5 cells), away from the edge, and its neighbours move aside by
  // what the ones before them grew, so they never overlap. Worked out from
  // the entries' resting positions, which the growth doesn't move, so the
  // pointer never chases its own effect.
  readonly property real magnify: Math.max(1, Config.o.dock.magnify)
  // Where the pointer is along the dock (-1 off it), and the same for the
  // magnification, which settles back while the menu or the previews are
  // open: an icon still growing as the drawer grows for its windows was two
  // motions at once.
  // Measured on the dock itself, not the icons grid: the grid's own
  // HoverHandler is under the cells' own MouseAreas, and one there can
  // keep it from seeing the pointer.
  readonly property real pointerPos: dockHover.hovered && dragKey === "" && !menuOpen
    ? (vertical ? dockHover.point.position.y - icons.y : dockHover.point.position.x - icons.x)
    : hoveredIndex >= 0 ? centres[hoveredIndex] : -1
  readonly property real hoverPos: previewOpen ? -1 : pointerPos
  // 0 at rest, 1 under the pointer: eases the growth in and out as the
  // pointer arrives and leaves, but follows it directly in between.
  property real magOn: hoverPos >= 0 ? 1 : 0
  Behavior on magOn { Anim { type: "fastSpatial" } }
  property real lastPos: -1
  onHoverPosChanged: if (hoverPos >= 0) lastPos = hoverPos
  // Resting centres along the dock, and sizes, of each entry.
  function sizeOf(e) { return e.kind === "divider" ? Tk.px(1) + gap : cell }
  readonly property var centres: {
    const out = []
    let p = 0
    for (const e of entries) { const s = sizeOf(e); out.push(p + s / 2); p += s + gap }
    return out
  }
  readonly property var scales: {
    const range = cell * 2.5
    return entries.map((e, i) => {
      if (e.kind !== "app" || magnify <= 1 || lastPos < 0) return 1
      const d = Math.abs(lastPos - centres[i])
      return 1 + (magnify - 1) * magOn * (d < range ? (Math.cos(Math.PI * d / range) + 1) / 2 : 0)
    })
  }
  readonly property var shifts: {
    const grow = entries.map((e, i) => (scales[i] - 1) * sizeOf(e))
    const total = grow.reduce((a, b) => a + b, 0)
    let before = 0
    return grow.map(g => { const s = before + g / 2 - total / 2; before += g; return s })
  }
  // The app under the pointer, for its name label and previews. The cell
  // itself reports it: a pointer over a cell is a MouseArea with hover on,
  // and the root HoverHandler doesn't reliably see it through that.
  readonly property int hoveredIndex: {
    if (!hoveredKey) return -1
    for (let i = 0; i < entries.length; i++)
      if (entries[i].kind === "app" && entries[i].app.key === hoveredKey) return i
    return -1
  }

  // ------------------------------------------------------- drag to reorder
  // A pinned app dragged along the dock lands where it is dropped; an open
  // app dropped among the pins is pinned there.
  property string dragKey: ""
  property real dragOffset: 0
  function dropAt(index, offset) {
    const e = entries[index]
    if (!e || e.kind !== "app" || !e.app.id) return
    const pos = centres[index] + offset
    // The first pin it lands before (none: after the last); placed by id,
    // since dock.pinned can hold ids the dock doesn't show.
    let before = "", lastPin = -1
    for (let i = 0; i < entries.length; i++) {
      const x = entries[i]
      if (x.kind !== "app" || !x.app.pinned) continue
      lastPin = i
      if (!before && x.app.key !== e.app.key && centres[i] > pos) before = x.app.id
    }
    // An open app joins the pins only when dropped among them.
    if (!e.app.pinned && (lastPin < 0 ? offset > -cell : pos > centres[lastPin] + cell)) return
    DockService.placePin(e.app.id, before)
  }

  // The Repeater's model: one key per entry, reassigned only when the keys
  // or their order change. Window events rebuild `entries` all the time (a
  // focus change is one), and a rebuilt model would destroy every icon --
  // the one being dragged included, losing its release. Each icon looks its
  // data up by key instead.
  property var slotKeys: []
  readonly property var entryByKey: {
    const m = {}
    for (const e of entries) m[e.kind === "divider" ? "|divider" : e.app.key] = e
    return m
  }
  function syncKeys() {
    const k = entries.map(e => e.kind === "divider" ? "|divider" : e.app.key)
    if (k.join("\n") === slotKeys.join("\n")) return
    slotKeys = k
    // The icons were rebuilt: a drag in progress has lost its icon.
    dragKey = ""
    dragOffset = 0
  }
  onEntriesChanged: syncKeys()
  Component.onCompleted: syncKeys()

  readonly property real iconsW: icons.implicitWidth
  readonly property real iconsH: icons.implicitHeight
  // The panel beside the icons: the menu, or the previews.
  readonly property var panel: menuOpen ? menu : previewOpen ? previews : null
  readonly property real menuW: panel ? panel.width : 0
  readonly property real menuH: panel ? panel.height : 0
  readonly property real menuGap: panel ? gap : 0

  // Its breadth with neither panel open: what an always-out dock reserves,
  // so opening the menu or the previews doesn't move the windows.
  readonly property real restBreadth: (empty ? cell : (vertical ? iconsW : iconsH)) + pad * 2
  // How far the drawer has grown towards holding the panel (0..1): the panel
  // fades in with it, so it never shows before there is room for it.
  readonly property real grown: {
    const full = (vertical ? implicitWidth : implicitHeight) - restBreadth
    const now = (vertical ? width : height) - restBreadth
    return full > 0 ? Math.max(0, Math.min(1, now / full)) * Math.max(0, Math.min(1, now / full)) : 1
  }

  implicitWidth: full
    ? Math.max(fullMinWidth, (empty ? cell : iconsW + gap + cell) + pad * 2, menuW + pad * 2)
    : empty ? cell + pad * 2 : (vertical ? iconsW + menuGap + menuW : Math.max(iconsW, menuW)) + pad * 2
  implicitHeight: empty ? cell + pad * 2
    : (vertical ? Math.max(iconsH, menuH) : iconsH + menuGap + menuH) + pad * 2

  Rectangle {
    x: icons.x - root.platePad
    y: icons.y - root.platePad
    width: icons.width + (allAppsTile.visible ? root.gap + allAppsTile.width : 0) + root.platePad * 2
    height: icons.height + root.platePad * 2
    radius: Tk.rounding.large
    color: Colours.m3surfaceContainer
    // The drawers' cards sit on a faint inner rim; the dock's plate needs the
    // same line so it reads as a card inside the drawer, not a flat cutout.
    border.width: 1
    border.color: Qt.alpha(Colours.m3outlineVariant, 0.7)
  }

  // Nothing pinned and nothing running: one clear way into the launcher,
  // so the edge's hover isn't a dead strip.
  Item {
    visible: root.empty
    anchors.horizontalCenter: parent.horizontalCenter
    y: Math.round((root.height - root.cell) / 2)
    width: root.cell
    height: root.cell
    MIcon {
      anchors.centerIn: parent
      text: "apps"
      size: root.cell * 0.55
      color: Colours.m3onSurfaceVariant
    }
    StateLayer {
      width: parent.width
      height: root.cell
      radius: root.cell / 2
      cursorShape: Qt.PointingHandCursor
      onClicked: root.launcherRequested()
    }
  }

  Grid {
    id: icons
    visible: !root.empty
    rows: root.vertical ? 0 : 1
    columns: root.vertical ? 1 : 0
    spacing: root.gap
    // Measured from the dock's edge, so they stay put while the drawer
    // grows away from it for the menu or the previews (its size animates;
    // placing them from the panel's final size made them jump out of the
    // still-small drawer and back).
    readonly property real rowW: width + (allAppsTile.visible ? root.gap + allAppsTile.width : 0)
    x: root.vertical ? (root.edge === "left" ? root.pad : root.width - root.pad - width) : Math.round((root.width - rowW) / 2)
    y: root.vertical ? Math.round((root.height - height) / 2)
      : (root.edge === "top" ? root.pad : root.height - root.pad - height)

    Repeater {
      model: root.slotKeys
      Loader {
        id: slot
        required property string modelData
        required property int index
        readonly property var entry: root.entryByKey[modelData] || { kind: "divider" }
        readonly property bool dragged: entry.kind === "app" && root.dragKey === modelData
        readonly property real shift: (root.shifts[index] || 0) + (dragged ? root.dragOffset : 0)
        z: dragged ? 1 : 0
        transform: Translate { x: root.vertical ? 0 : slot.shift; y: root.vertical ? slot.shift : 0 }
        sourceComponent: entry.kind === "divider" ? divider : appCell
        Component {
          id: appCell
          DockItem {
            modelData: slot.entry.app
            cell: root.cell
            full: root.full
            names: root.names
            edge: root.edge
            mag: root.scales[slot.index] || 1
            menuShown: root.menuKey === modelData.key
            highlighted: root.hoveredKey === modelData.key
            previewOpen: root.previewOpen
            onDismissRequested: root.dismissRequested()
            onHoverChanged: hovered => {
              if (hovered) root.hoveredKey = modelData.key
              else if (root.hoveredKey === modelData.key) root.hoveredKey = ""
            }
            onMenuRequested: root.menuKey = root.menuKey === modelData.key ? "" : modelData.key
            onDragMoved: d => { root.dragKey = modelData.key; root.dragOffset = d }
            // The drop rebuilds the entries, and with them this delegate:
            // clear the drag first and drop from outside it.
            onDragEnded: d => { const i = slot.index; root.dragKey = ""; root.dragOffset = 0; Qt.callLater(() => root.dropAt(i, d)) }
          }
        }
      }
    }
  }

  // The one app-adjacent way to the launcher. It sits after the icons as a
  // tile of its own, so the full drawer needs no header row.
  Rectangle {
    id: allAppsSep
    visible: allAppsTile.visible
    x: allAppsTile.x - Math.ceil(root.gap / 2)
    y: allAppsTile.y + Math.round((root.cell - Tk.px(34)) / 2)
    width: 1
    height: Tk.px(34)
    color: Colours.m3outlineVariant
  }
  Item {
    id: allAppsTile
    visible: root.full && !root.empty
    x: icons.x + icons.width + root.gap
    y: icons.y
    width: root.cell
    height: root.cell + (root.names === "always" ? Tk.px(24) : 0)

    Spring {
      id: allAppsSpring
      value: 1
      target: allAppsPress.pressed ? 0.9 : 1
      stiffness: 520
      damping: 24
    }
    transform: Scale {
      origin.x: width / 2
      origin.y: height / 2
      xScale: allAppsSpring.value
      yScale: allAppsSpring.value
    }

    MIcon {
      anchors.horizontalCenter: parent.horizontalCenter
      y: Math.round((root.cell - height) / 2)
      text: "apps"
      size: root.cell * 0.54
      color: Colours.m3onSurfaceVariant
    }
    MText {
      visible: root.names === "always" || (root.names === "hover" && allAppsPress.containsMouse)
      width: root.cell
      y: root.cell + Tk.px(4)
      text: "All apps"
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      font.pointSize: Tk.label.medium
      color: Colours.m3onSurfaceVariant
    }
    MouseArea {
      id: allAppsPress
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.launcherRequested()
    }
  }

  Component {
    id: divider
    Item {
      implicitWidth: root.vertical ? root.cell : Tk.px(1) + root.gap
      implicitHeight: root.vertical ? Tk.px(1) + root.gap : (root.names === "always" ? root.cell + (root.full ? Tk.px(24) : Tk.px(18)) : root.cell)
      Rectangle {
        anchors.centerIn: parent
        width: root.vertical ? root.cell * 0.6 : 1
        height: root.vertical ? 1 : root.cell * 0.6
        color: Colours.m3outlineVariant
      }
    }
  }

  // ---------------------------------------------------------------- menu
  readonly property var menuActions: {
    const it = menuApp
    if (!it) return []
    const out = []
    if (it.entry) out.push({ id: "pin", icon: it.pinned ? "keep_off" : "keep", label: it.pinned ? "Unpin from dock" : "Pin to dock" })
    if (it.entry) out.push({ id: "new", icon: "add", label: "New window" })
    if (it.windows.length) {
      out.push({ id: "here", icon: "move_down", label: it.windows.length > 1 ? "Move windows here" : "Move here" })
      out.push({ id: "close", icon: "close", label: it.windows.length > 1 ? "Close " + it.windows.length + " windows" : "Close", danger: true })
    }
    return out
  }
  function run(action) {
    const it = menuApp
    closeMenu()
    if (!it) return
    if (action === "pin") DockService.setPinned(it.id, !it.pinned)
    else if (action === "new") DockService.launch(it)
    else if (action === "here") for (const w of it.windows) Sys.moveWindow(w.address, String(workspaceId))
    else if (action === "close") DockService.closeAll(it)
  }

  Grid {
    id: previews
    readonly property var app: root.previewApp || ({ windows: [] })
    visible: root.previewOpen
    opacity: root.previewOpen ? root.grown : 0
    rows: root.vertical ? 0 : 1
    columns: root.vertical ? 1 : 0
    spacing: root.gap
    // Right past the icons, away from the edge, uncovered as the drawer grows.
    x: root.vertical ? (root.edge === "left" ? icons.x + root.iconsW + root.gap : icons.x - root.gap - width) : Math.round((root.width - width) / 2)
    y: root.vertical ? Math.round((root.height - height) / 2) : (root.edge === "top" ? icons.y + root.iconsH + root.gap : icons.y - root.gap - height)

    Repeater {
      // At most five; the rest are a click away (cycling).
      model: root.previewOpen ? previews.app.windows.slice(0, 5) : []
      DockPreview {
        required property var modelData
        win: modelData
        live: root.previewOpen
        onActivated: { Sys.focusWindow(modelData.address); root.previewKey = "" }
        onCloseRequested: Sys.closeWindow(modelData.address)
      }
    }
  }

  Column {
    id: menu
    visible: root.menuOpen
    opacity: root.menuOpen ? root.grown : 0
    width: Tk.px(220)
    // Right past the icons, away from the edge, uncovered as the drawer grows.
    x: root.vertical ? (root.edge === "left" ? icons.x + root.iconsW + root.gap : icons.x - root.gap - width) : Math.round((root.width - width) / 2)
    y: root.vertical ? Math.round((root.height - height) / 2) : (root.edge === "top" ? icons.y + root.iconsH + root.gap : icons.y - root.gap - height)
    spacing: Tk.px(2)

    MText {
      width: parent.width
      leftPadding: Tk.padding.medium
      rightPadding: Tk.padding.medium
      topPadding: Tk.padding.small
      bottomPadding: Tk.padding.small
      text: root.menuApp ? root.menuApp.name : ""
      elide: Text.ElideRight
      font.pointSize: Tk.label.large
      weight: Font.Medium
      color: Colours.m3onSurfaceVariant
    }
    Repeater {
      model: root.menuActions
      Rectangle {
        required property var modelData
        width: menu.width
        implicitHeight: row.implicitHeight + Tk.padding.small * 2
        radius: Tk.rounding.small
        color: "transparent"
        Row {
          id: row
          anchors.verticalCenter: parent.verticalCenter
          x: Tk.padding.medium
          spacing: Tk.spacing.medium
          MIcon {
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.icon
            size: Tk.iconSize.medium
            color: modelData.danger ? Colours.m3error : Colours.m3onSurface
          }
          MText {
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.label
            font.pointSize: Tk.body.medium
            color: modelData.danger ? Colours.m3error : Colours.m3onSurface
          }
        }
        StateLayer {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.run(modelData.id)
        }
      }
    }
  }
}
