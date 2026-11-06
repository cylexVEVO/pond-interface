import QtQuick
import Quickshell
import ".." as Shell

// Native layer-shell-compatible tooltip. It never grabs input or keyboard focus.
Item {
  id: root
  property string text: ""
  property bool hovered: false
  property Item target: parent
  property bool ready: false
  onHoveredChanged: {
    ready = false;
    if (hovered) delay.restart(); else delay.stop();
  }
  Timer { id: delay; interval: 250; onTriggered: root.ready = true }
  PopupWindow {
    visible: root.hovered && root.ready && !!root.text && root.target && root.target.visible
    anchor.item: root.target
    anchor.edges: Edges.Right | Edges.Top
    anchor.gravity: Edges.Right | Edges.Bottom
    anchor.margins.right: 6
    grabFocus: false
    color: "transparent"
    mask: Region {}
    implicitWidth: Math.min(280, Math.ceil(label.implicitWidth) + 20)
    implicitHeight: Math.ceil(label.implicitHeight) + 20
    Rectangle {
      anchors.fill: parent
      radius: 8
      color: Shell.PanelStyle.surface
      border.width: 1
      border.color: Shell.Theme.sidebarCardOutline
    }
    Text {
      id: label
      x: 10; y: 10
      width: parent.width - 20
      text: root.text
      textFormat: Text.PlainText
      wrapMode: Text.WrapAnywhere
      color: Shell.Theme.colors.text
      font.family: Shell.Theme.fontFamily
      font.pixelSize: 12
    }
  }
}
