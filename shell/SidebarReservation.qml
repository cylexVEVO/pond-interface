import QtQuick
import Quickshell
import Quickshell.Wayland

// Keep compositor reservation separate from the wide overlay used for cards,
// shadows and popouts. Width changes produce a configure/commit cycle; Zen
// unmaps this surface altogether. The visible sidebar always remains an overlay.
PanelWindow {
  required property int reservedWidth
  visible: reservedWidth > 0
  implicitWidth: Math.max(1, reservedWidth)
  anchors { left: true; top: true; bottom: true }
  color: "transparent"
  mask: Region {}
  exclusionMode: ExclusionMode.Auto
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.namespace: "pond-sidebar-reservation"
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
}
