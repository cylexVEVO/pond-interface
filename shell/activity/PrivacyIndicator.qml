import QtQuick
import "." as Activity

// Layout must not depend on effective child visibility: hiding a Row also
// hides its children, which can keep its implicitWidth at zero on re-entry.
Item {
  id: root
  readonly property bool presented: width > 0
  width: audio.slotWidth + camera.slotWidth + video.slotWidth + unavailable.slotWidth
  height: presented ? 8 : 0
  visible: presented

  component Light: Activity.Presence {
    id: light
    property var kinds: []
    property color dotColor: "#A1B7C8"
    property bool hollow: false
    property bool error: false
    readonly property var streams: Activity.State.privacyStreams.filter(s => kinds.includes(s.kind))
    readonly property real slotWidth: shown || reveal > 0.001 ? 10 : 0
    shown: error ? Activity.State.detectionFailed : streams.length > 0
    width: 10; height: 8
    Accessible.role: Accessible.StaticText
    Accessible.name: error ? "Recording detection unavailable" : Activity.State.describe(streams)
    Rectangle {
      anchors.centerIn: parent
      width: 6; height: 6; radius: 3
      color: light.hollow ? "transparent" : light.dotColor
      border.width: light.hollow ? 1 : 0
      border.color: light.dotColor
    }
    HoverHandler { id: pointer }
    Activity.Hint {
      hovered: light.shown && pointer.hovered
      text: light.error ? Activity.State.audioError : Activity.State.describe(light.streams)
    }
  }

  Light {
    id: audio
    kinds: ["microphone", "capture", "monitor"]
    dotColor: "#F5AE62"
  }
  Light {
    id: camera
    x: audio.slotWidth
    kinds: ["camera"]
    dotColor: "#79CE8B"
  }
  Light {
    id: video
    x: audio.slotWidth + camera.slotWidth
    kinds: ["video", "screen"]
    hollow: true
  }
  Light {
    id: unavailable
    x: audio.slotWidth + camera.slotWidth + video.slotWidth
    error: true
    hollow: true
  }
}
