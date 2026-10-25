import QtQuick
import "../.."

// Caelestia components/containers/StyledFlickable.qml: overshoots and springs
// back with the standard curve; the fake flick afterwards resets Qt's
// velocity so the next wheel scroll doesn't stall.
Flickable {
  id: root
  property bool doneFakeFlick

  maximumFlickVelocity: 3000
  rebound: Transition {
    onRunningChanged: {
      if (!running && !root.doneFakeFlick) {
        root.doneFakeFlick = true
        root.flick(1, 1)
        root.flick(-1, -1)
        Qt.callLater(() => root.cancelFlick())
      }
    }
    Anim { properties: "x,y" }
  }
  Timer { running: root.doneFakeFlick; interval: 10; onTriggered: root.doneFakeFlick = false }

  // Wheel scrolling. Qt's own step (about 60 px a notch, further damped by
  // Omarchy's global scroll_factor of 0.4) felt slow in Omacale's drawers, so
  // one notch moves `wheelStep` px here; precise devices (touchpad, high-res
  // wheel) follow the pointer times `preciseFactor`. Tune these two numbers.
  property real wheelStep: 180
  property real preciseFactor: 2.0
  WheelHandler {
    onWheel: (event) => {
      let dy = event.angleDelta.y ? event.angleDelta.y / 120 * root.wheelStep
                                   : event.pixelDelta.y * root.preciseFactor
      if (!dy) return
      const min = root.originY
      const max = root.originY + Math.max(0, root.contentHeight - root.height)
      root.contentY = Math.max(min, Math.min(max, root.contentY - dy))
      event.accepted = true
    }
  }
}
