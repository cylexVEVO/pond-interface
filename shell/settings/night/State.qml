pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  id: root
  property var settings: ({enabled: false, intensity: 0.5, schedule: "manual", start: "20:00", end: "07:00", latitude: "", longitude: ""})
  property string error: ""
  property bool ready: false
  readonly property string summary: !settings.enabled ? "Off" : error ? "Unavailable" : settings.schedule === "manual" ? "On" : "Scheduled"
  property var pending: ({})

  function update(patch) {
    pending = Object.assign({}, pending, patch);
    delay.restart();
  }
  Timer {
    id: delay; interval: 250
    onTriggered: {
      if (!root.ready) return;
      service.write(JSON.stringify(root.pending) + "\n");
      root.pending = ({});
    }
  }
  Process {
    id: service
    command: ["python3", Quickshell.shellDir + "/settings/night/control.py"]
    running: true
    stdinEnabled: true
    stdout: SplitParser {
      onRead: data => {
        try {
          const result = JSON.parse(data);
          root.settings = result.settings;
          root.error = result.error;
          root.ready = true;
        } catch (e) { root.error = "Could not read night display settings."; }
      }
    }
    onExited: {
      root.ready = false;
      root.error = "Night display service stopped. Restart the shell to retry.";
    }
  }
}
