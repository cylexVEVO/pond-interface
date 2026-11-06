import QtQuick
import QtQuick.Effects
import Quickshell.Widgets
import ".." as Shell
import "../activity" as Activity

// One live window marker. The same primitive scales between the 40px
// expanded rail and the 32px collapsed stack while retaining app activation
// across both layouts.
Item {
  id: root

  property var windowData: ({})
  property real controlSize: Shell.Theme.workspaceControlSize
  property bool interactive: true
  property bool lifted: false
  signal activated(var windowId)

  readonly property var sleepRequests: Activity.State.sleepRequests(windowData.appId || "")
  readonly property var playback: Activity.State.playbackStreams(windowData.appId || "")
  readonly property string activityDescription: [
      sleepRequests.map(i => Activity.State.inhibitionDescription(i)).join("\n"),
      Activity.State.describe(playback)].filter(s => s !== "").join("\n")
  readonly property bool hovered: pointer.containsMouse

  implicitWidth: controlSize
  implicitHeight: controlSize

  Shell.Shadow {
    anchors.fill: chrome
    cornerRadius: chrome.radius
    shadows: root.visible && root.lifted && Shell.Theme.translucent ? Shell.PanelStyle.controlShadows : []
  }

  Rectangle {
    id: chrome
    anchors.fill: parent
    radius: width / 2
    antialiasing: true
    // Fade alpha without interpolating the fill through transparent black.
    color: root.lifted ? Shell.Theme.workspaceDragBackground : root.hovered ? Shell.Theme.workspaceControlHover
        : Qt.rgba(Shell.Theme.workspaceControlHover.r, Shell.Theme.workspaceControlHover.g,
                  Shell.Theme.workspaceControlHover.b, 0)
    border.color: root.lifted ? "#CBA6F7" : Shell.Theme.workspaceIconOutline
    border.width: root.hovered ? 0 : Shell.Theme.sidebarStrokeWidth
    layer.enabled: root.lifted && !Shell.Theme.translucent
    layer.effect: MultiEffect {
      shadowEnabled: true
      shadowBlur: 0.5
      blurMax: 10
      shadowOpacity: 0.4
      shadowHorizontalOffset: 2
      shadowVerticalOffset: 5
    }

    Behavior on color {
      ColorAnimation {
        duration: Shell.Theme.sidebarHoverDuration
        easing.type: Easing.OutCubic
      }
    }
  }

  IconImage {
    anchors.centerIn: parent
    visible: (root.windowData.iconSource || "") !== ""
    width: Shell.Theme.workspaceIconSize * (root.lifted ? Shell.Theme.workspaceDragGlyphScale : 1)
    height: width
    source: root.windowData.iconSource || ""
    asynchronous: true
    smooth: true
    opacity: Shell.Theme.translucent || root.hovered || root.lifted ? 1.0 : 0.9

    Behavior on opacity { Shell.HoverAnimation {} }
  }

  Loader {
    anchors.centerIn: parent
    // Regular app icons do not need the terminal's SVG animation frames.
    active: (root.windowData.dotState || "") !== ""
    sourceComponent: TerminalIndicator {
      dotState: root.windowData.dotState || "read"
      loaderVariant: root.windowData.loaderVariant || 1
      scale: root.controlSize / Shell.Theme.workspaceControlSize
          * (root.lifted ? Shell.Theme.workspaceDragGlyphScale : 1)
    }
  }

  // A quiet amber ring belongs to the app causing the sleep inhibition.
  Rectangle {
    anchors { right: parent.right; bottom: parent.bottom; margins: 3 }
    width: 7; height: 7; radius: 3.5
    color: Shell.PanelStyle.surface
    border.width: 1.5; border.color: "#F5AE62"
    visible: root.sleepRequests.length > 0
  }
  Image {
    anchors { left: parent.left; bottom: parent.bottom; margins: 2 }
    width: 8; height: 8
    source: "../assets/sound.svg"
    visible: root.playback.length > 0
  }
  Activity.Hint {
    hovered: pointer.containsMouse && !!root.activityDescription
    text: root.activityDescription
  }

  MouseArea {
    id: pointer
    anchors.fill: parent
    enabled: root.interactive
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      if (root.windowData.winId !== undefined)
        root.activated(root.windowData.winId);
    }
  }
}
