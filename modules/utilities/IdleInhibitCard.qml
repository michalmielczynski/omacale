import QtQuick
import QtQuick.Layouts
import "../.."

// Keep awake card (Caelestia utilities/cards/IdleInhibit.qml).
// Below Caelestia's header, melon: presets that keep the screen awake for a
// set time (15 / 30 / 60 minutes, as GNOME's Caffeine), since the switch
// alone is all-or-nothing.
GlassCard {
  id: root

  // Minutes; 0 would be the switch's own open-ended keep awake.
  readonly property var presets: [15, 30, 60]

  readonly property real nonAnimHeight: layout.implicitHeight + presetRow.implicitHeight + Tk.spacing.small
    + Tk.padding.extraLargeIncreased + (IdleService.enabled ? chip.implicitHeight + chip.anchors.topMargin : 0)

  function presetLabel(minutes) {
    return minutes >= 60 ? (minutes / 60) + " h" : minutes + " min"
  }

  // Clicking the preset that is running puts keep awake out again; any other
  // starts (or restarts) the timer at its own length.
  function choose(minutes) {
    if (IdleService.enabled && IdleService.timed && IdleService.timedMinutes === minutes)
      IdleService.disable()
    else
      IdleService.enableFor(minutes)
  }

  implicitHeight: nonAnimHeight
  radius: Tk.rounding.large
  fill: Colours.m3surfaceContainer
  clip: true

  RowLayout {
    id: layout
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.margins: Tk.padding.large
    spacing: Tk.spacing.medium

    Rectangle {
      implicitWidth: implicitHeight
      implicitHeight: icon.implicitHeight + Tk.padding.large
      radius: Tk.rounding.full
      color: IdleService.enabled ? Colours.m3secondary : Colours.m3secondaryContainer
      Behavior on color { CAnim {} }

      MIcon {
        id: icon
        anchors.centerIn: parent
        text: "coffee"
        size: Tk.iconSize.large
        color: IdleService.enabled ? Colours.m3onSecondary : Colours.m3onSecondaryContainer
        Behavior on color { CAnim {} }
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: 0

      MText {
        Layout.fillWidth: true
        text: "Keep awake"
        font.pointSize: Tk.body.medium
        elide: Text.ElideRight
      }
      MText {
        Layout.fillWidth: true
        text: IdleService.enabled ? "Preventing sleep mode" : "Normal power management"
        color: Colours.m3onSurfaceVariant
        font.pointSize: Tk.body.small
        elide: Text.ElideRight
      }
    }

    MSwitch {
      checked: IdleService.enabled
      onToggled: IdleService.toggle()
    }
  }

  RowLayout {
    id: presetRow
    anchors.top: layout.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: Tk.padding.large
    anchors.rightMargin: Tk.padding.large
    anchors.topMargin: Tk.spacing.small
    spacing: Tk.spacing.small

    Repeater {
      model: root.presets

      Rectangle {
        id: preset
        required property int modelData

        readonly property bool current: IdleService.enabled && IdleService.timed && IdleService.timedMinutes === modelData

        Layout.alignment: Qt.AlignVCenter
        implicitWidth: presetText.implicitWidth + Tk.padding.medium * 2
        implicitHeight: presetText.implicitHeight + Tk.padding.small
        radius: Tk.rounding.full
        color: current ? Colours.m3primary : Colours.m3secondaryContainer
        Behavior on color { CAnim {} }

        StateLayer {
          onClicked: root.choose(preset.modelData)
        }

        MText {
          id: presetText
          anchors.centerIn: parent
          text: root.presetLabel(preset.modelData)
          color: preset.current ? Colours.m3onPrimary : Colours.m3onSecondaryContainer
          font.pointSize: Math.round(Tk.body.small * 0.95)
          Behavior on color { CAnim {} }
        }
      }
    }

    Item { Layout.fillWidth: true }
  }

  Loader {
    id: chip
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.topMargin: Tk.spacing.large
    anchors.bottomMargin: IdleService.enabled ? Tk.padding.large : -implicitHeight
    anchors.leftMargin: Tk.padding.large

    opacity: IdleService.enabled ? 1 : 0
    scale: IdleService.enabled ? 1 : 0.5
    active: opacity > 0

    sourceComponent: Rectangle {
      implicitWidth: activeText.implicitWidth + Tk.padding.medium * 2
      implicitHeight: activeText.implicitHeight + Tk.padding.small
      radius: Tk.rounding.full
      color: Colours.m3primary

      MText {
        id: activeText
        anchors.centerIn: parent
        // A timer shows what is left of it, as GNOME's Caffeine does; the
        // open-ended keep awake keeps Caelestia's chip.
        text: IdleService.timed
          ? "Auto-off in " + IdleService.remainingText
          : "Active since " + (IdleService.enabledSince ? Sys.time(IdleService.enabledSince) : "just now")
        color: Colours.m3onPrimary
        font.pointSize: Math.round(Tk.body.small * 0.9)
      }
    }

    Behavior on anchors.bottomMargin { Anim {} }
    Behavior on opacity { Anim { type: "standardSmall" } }
    Behavior on scale { Anim {} }
  }

  Behavior on implicitHeight { Anim {} }
}
