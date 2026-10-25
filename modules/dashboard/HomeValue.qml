import QtQuick
import QtQuick.Layouts
import "../.."

// One number with a caption under it: the "Dom" tab's cards are mostly these
// (flows, temperatures, battery levels).
ColumnLayout {
  id: root
  property string label
  property string value
  property color valueColour: Colours.m3onSurface
  spacing: 0
  MText {
    text: root.value
    font.pointSize: Tk.title.small
    weight: Font.DemiBold
    color: root.valueColour
  }
  MText {
    text: root.label
    font.pointSize: Tk.label.small
    color: Colours.m3onSurfaceVariant
  }
}
