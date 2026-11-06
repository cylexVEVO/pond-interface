pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "settings" as Settings
import "notifications" as Notifications

Singleton {
  id: root
  property bool active: false
  // Session-only preference. Never rewrite saved lock/display/sleep timeouts.
  property bool keepAwake: false
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
