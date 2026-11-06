import QtQuick

// Interruptible entry/exit motion for quiet activity signals. Keep the item
// alive through its exit; nothing loops while the signal is active.
Item {
  id: root
  property bool shown: false
  property real reveal: shown ? 1 : 0
  visible: reveal > 0.001
  opacity: reveal
  transformOrigin: Item.Center
  scale: 0.65 + 0.35 * reveal
  enabled: shown
  Behavior on reveal {
    NumberAnimation {
      duration: root.shown ? 220 : 180
      easing.type: Easing.OutCubic
    }
  }
}
