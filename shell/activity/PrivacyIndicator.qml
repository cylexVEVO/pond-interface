import QtQuick
import "." as Activity

// Only active capture or failed detection adds a light; no idle-state control.
Row {
  id: root
  spacing: 0
  width: implicitWidth
  readonly property bool presented: implicitWidth > 0.01
  height: presented ? 8 : 0
  visible: presented
  Repeater {
    model: [
      {kinds: ["microphone", "capture", "monitor"], color: "#F5AE62", hollow: false, error: false},
      {kinds: ["camera"], color: "#79CE8B", hollow: false, error: false},
      {kinds: ["video", "screen"], color: "#A1B7C8", hollow: true, error: false},
      {kinds: [], color: "#A1B7C8", hollow: true, error: true}
    ]
    Activity.Presence {
      id: light
      required property var modelData
      readonly property var streams: Activity.State.privacyStreams.filter(s => modelData.kinds.includes(s.kind))
      shown: modelData.error ? Activity.State.detectionFailed : streams.length > 0
      width: 10 * reveal; height: 8
      Accessible.role: Accessible.StaticText
      Accessible.name: modelData.error ? "Recording detection unavailable" : Activity.State.describe(streams)
      Rectangle {
        anchors.centerIn: parent
        width: 6; height: 6; radius: 3
        color: light.modelData.hollow ? "transparent" : light.modelData.color
        border.width: light.modelData.hollow ? 1 : 0
        border.color: light.modelData.color
      }
      HoverHandler { id: pointer }
      Activity.Hint {
        hovered: light.shown && pointer.hovered
        text: light.modelData.error ? Activity.State.audioError : Activity.State.describe(light.streams)
      }
    }
  }
}
