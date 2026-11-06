pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "settings" as Settings
import "notifications" as Notifications
import "settings/system" as System

Singleton {
  id: root
  property bool active: false
  readonly property bool keepAwake: System.Idle.zenKeepAwake
  readonly property bool holdingIdle: active && keepAwake
  onActiveChanged: {
    Notifications.State.transientId = "";
    Notifications.State.closePanel();
    if (active) Settings.State.close();
  }
  function toggle() { active = !active; }
  IpcHandler {
    target: "zen"
    function toggle() { root.toggle(); }
  }
}
