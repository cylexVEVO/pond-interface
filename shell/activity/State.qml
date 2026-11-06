pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  id: root
  property var streams: []
  property var inhibitors: []
  property string audioError: "Checking audio activity…"
  property string sleepError: "Checking sleep inhibitors…"
  readonly property bool microphone: streams.some(s => s.kind === "microphone")
  readonly property bool systemAudio: streams.some(s => s.kind === "monitor")
  readonly property bool uncertainCapture: streams.some(s => s.kind === "capture")
  readonly property bool capturing: microphone || systemAudio || uncertainCapture
  readonly property string captureLabel: [microphone ? "Microphone" : "",
      systemAudio ? "System audio" : "", uncertainCapture ? "Audio (source uncertain)" : ""]
      .filter(label => label !== "").join(" and ") + " capture active"
  readonly property bool playing: streams.some(s => s.kind === "playback" && s.muted !== true)
  readonly property bool blocking: inhibitors.some(i => i.mode.startsWith("block"))
  function refresh() { if (!query.running) query.running = true; }
  Component.onCompleted: refresh()
  Timer { interval: 3000; running: true; repeat: true; onTriggered: root.refresh() }
  Process {
    id: query
    command: ["python3", Quickshell.shellDir + "/activity/query.py"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const data = JSON.parse(text);
          root.streams = data.streams;
          root.inhibitors = data.inhibitors;
          root.audioError = data.audioError;
          root.sleepError = data.sleepError;
        } catch (e) {
          root.streams = []; root.inhibitors = [];
          root.audioError = "Audio activity unavailable";
          root.sleepError = "Sleep inhibitors unavailable";
        }
      }
    }
  }
}
