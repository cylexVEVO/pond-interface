import QtQuick
import Quickshell
import Quickshell.Wayland
import "." as Activity
import ".." as Shell
import "../audio" as Audio
import "../media" as Media
import "../settings" as Settings
import "../settings/system" as System

PanelWindow {
  id: root
  required property var bar
  property string focusMessage: ""
  screen: bar.screen
  visible: bar.popup === "activity"
  color: "transparent"
  anchors { left: true; right: true; top: true; bottom: true }
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "pond-activity"
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  WlrLayershell.exclusionMode: ExclusionMode.Ignore
  // Let sidebar attention controls and the Zen exit receive clicks directly.
  mask: Region {
    intersection: Intersection.Subtract
    regions: [root.bar.mask]
  }
  onVisibleChanged: if (visible) { Activity.State.refresh(); card.forceActiveFocus(); }
  Component.onCompleted: if (visible) card.forceActiveFocus()
  MouseArea { anchors.fill: parent; onClicked: root.bar.popup = "" }
  Shell.Card {
    id: card
    x: Shell.Zen.active ? 40 : Shell.Theme.sidebarOuterMargin + root.bar.cardWidth + 10
    y: 20
    width: 356
    height: Math.min(root.height - 40, contents.height + 32)
    focus: true
    Keys.onEscapePressed: root.bar.popup = ""
    Flickable {
      anchors { fill: parent; margins: 16 }
      contentHeight: contents.height
      clip: true
      Column {
        id: contents
        width: parent.width
        spacing: 12
        Text { text: "Why is this happening?"; color: Shell.Theme.colors.text; font.pixelSize: 19 }
        Text {
          width: parent.width; wrapMode: Text.Wrap; textFormat: Text.PlainText
          color: Shell.Theme.colors.text; font.pixelSize: 13
          text: Activity.State.audioError || "Running audio streams (not a measurement of audible sound). App names are supplied by apps; browser tabs and virtual microphone sources may be unknown."
        }
        Repeater {
          model: Activity.State.streams
          Column {
            id: streamRow
            required property var modelData
            width: contents.width; spacing: 4
            Text {
              width: parent.width; wrapMode: Text.Wrap; textFormat: Text.PlainText
              color: Shell.Theme.colors.text; font.pixelSize: 13
              text: streamRow.modelData.name + " · " + ({playback: "playing audio", microphone: "using microphone", monitor: "recording system audio", capture: "capturing audio · source uncertain"})[streamRow.modelData.kind]
                  + (streamRow.modelData.muted === true ? " (muted)" : "")
            }
            Shell.ActionButton {
              property var stream: streamRow.modelData
              text: "Go to app"; height: 30
              onClicked: {
                if (Shell.NiriMsg.focusApp(stream.name, stream.appId)) root.bar.popup = "";
                else root.focusMessage = "No matching app window found. This may be a background service.";
              }
            }
          }
        }

        Text { visible: !Activity.State.audioError && !Activity.State.streams.length; text: "No running audio streams reported."; color: Shell.Theme.colors.text; font.pixelSize: 13 }
        Text {
          visible: !!root.focusMessage
          width: parent.width; wrapMode: Text.Wrap; text: root.focusMessage
          color: Shell.Theme.colors.text; font.pixelSize: 13
        }
        Row {
          spacing: 8
          Shell.ActionButton { width: 154; text: Audio.State.source?.audio?.muted ? "Unmute microphone" : "Mute microphone"; interactive: Audio.State.hasInput; onClicked: Audio.State.toggleInputMute() }
          Shell.ActionButton { width: 154; text: "Sound controls"; onClicked: { root.bar.popup = ""; root.bar.togglePanel("audio"); } }
        }
        Row {
          spacing: 8
          Shell.ActionButton { width: 154; text: Audio.State.outputMuted ? "Unmute output" : "Mute output"; interactive: Audio.State.hasOutput; onClicked: Audio.State.toggleOutputMute() }
          Shell.ActionButton { width: 154; text: "Pause media"; interactive: Media.State.isPlaying && Media.State.canPlayPause; onClicked: Media.State.playPause() }
        }
        Text {
          width: parent.width; wrapMode: Text.Wrap; color: Shell.Theme.colors.text; font.pixelSize: 13
          text: Activity.State.sleepError || "Sleep & idle requests · logind. Delays briefly postpone sleep; they do not block it indefinitely. Compositor-only inhibitors are not exposed here."
        }
        Repeater {
          model: Activity.State.inhibitors
          Text {
            required property var modelData
            width: contents.width; wrapMode: Text.Wrap; textFormat: Text.PlainText
            color: Shell.Theme.colors.text; font.pixelSize: 13
            text: modelData.name + " · " + modelData.mode + " · " + modelData.what + "\n" + modelData.reason
          }
        }
        Text {
          visible: !Activity.State.sleepError && !Activity.State.inhibitors.length
          text: "No logind sleep or idle requests reported."
          color: Shell.Theme.colors.text; font.pixelSize: 13
        }
        Text {
          width: parent.width; wrapMode: Text.Wrap; color: Shell.Theme.colors.text; font.pixelSize: 13
          text: Shell.Zen.holdingIdle ? "Pond Zen: automatic lock, display off and sleep paused. Manual lock and sleep still work."
              : "Pond timers: lock " + System.Idle.label(System.Idle.current.lock) + "; display " + System.Idle.label(System.Idle.current.display) + "; sleep " + System.Idle.label(System.Idle.current.sleep) + "."
        }
        Shell.ActionButton { width: parent.width; text: "Lock & sleep settings"; onClicked: { root.bar.popup = ""; Settings.State.open(root.bar.screen.name, "lock"); } }
        Text {
          width: parent.width; wrapMode: Text.Wrap; color: Shell.Theme.colors.text; font.pixelSize: 12
          text: "Stay-awake affects Pond timers only; other power managers and manual sleep can still suspend. Microphone mute affects the default input only; it does not revoke app access."
        }
        Shell.ActionButton { width: parent.width; text: Shell.Zen.keepAwake ? "Stay awake in Zen: on" : "Stay awake in Zen: off"; onClicked: Shell.Zen.keepAwake = !Shell.Zen.keepAwake }
        Shell.ActionButton { width: parent.width; text: Shell.Zen.active ? "Exit Zen" : "Enter Zen"; onClicked: { root.bar.popup = ""; Shell.Zen.toggle(); } }
        Shell.ActionButton { width: parent.width; text: "Close"; onClicked: root.bar.popup = "" }
      }
    }
  }
}
