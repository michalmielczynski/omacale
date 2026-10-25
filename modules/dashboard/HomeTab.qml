import QtQuick
import QtQuick.Layouts
import "../.."

// "Dom": native Omacale cards for the three things that used to be hosted
// Omarchy bar widgets (melon.rekuperacja, melon.lights, melon.sony). The plugin
// pill is off, so those plugins draw nothing in the bar any more and their
// helpers are driven straight from here, one card each, polling only while this
// tab is the visible page.
Item {
  id: root
  property bool active: false

  implicitWidth: content.implicitWidth
  implicitHeight: content.implicitHeight

  GridLayout {
    id: content
    anchors.fill: parent
    rowSpacing: Tk.spacing.medium
    columnSpacing: Tk.spacing.medium

    Card {
      Layout.row: 0; Layout.column: 0; Layout.columnSpan: 2
      Layout.preferredWidth: Tk.px(520)
      Layout.preferredHeight: Tk.px(330)
      RekuperacjaCard { anchors.fill: parent; anchors.margins: Tk.padding.large; active: root.active }
    }

    Card {
      Layout.row: 0; Layout.column: 2; Layout.columnSpan: 2
      Layout.preferredWidth: Tk.px(520)
      Layout.preferredHeight: Tk.px(330)
      LightsCard { anchors.fill: parent; anchors.margins: Tk.padding.large; active: root.active }
    }

    Card {
      Layout.row: 1; Layout.column: 0; Layout.columnSpan: 4
      Layout.preferredWidth: Tk.px(1060)
      Layout.preferredHeight: Tk.px(160)
      SonyCard { anchors.fill: parent; anchors.margins: Tk.padding.large; active: root.active }
    }
  }

  component Card: Rectangle { color: Colours.m3surfaceContainer; radius: Tk.rounding.extraLarge }
}
