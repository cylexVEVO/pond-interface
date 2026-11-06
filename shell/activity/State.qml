pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".." as Shell

Singleton {
  id: root
  property var streams: []
  property var inhibitors: []
  property string audioError: "Checking audio activity…"
  property string sleepError: "Checking sleep inhibitors…"
  readonly property bool detectionFailed: !!audioError && !audioError.startsWith("Checking")
  readonly property var privacyStreams: streams.filter(s => s.kind !== "playback")
  function describe(items) {
    const labels = {microphone: "Microphone", capture: "Audio capture (source unknown)",
      monitor: "System audio recording", camera: "Camera", video: "Video capture (source unknown)",
      screen: "Screen recording", playback: "Playing audio"};
    return items.map(s => s.name + " · " + labels[s.kind]).join("\n");
  }
  function inhibitionDescription(request) {
    const what = request.what.split(":");
    const sleep = what.includes("sleep"), idle = what.includes("idle");
    const target = sleep && idle ? "sleep and automatic idle actions"
        : sleep ? "sleep" : "automatic idle actions";
    return (request.mode === "block-weak" ? "May prevent " : "Preventing ")
        + target + " · " + request.reason;
  }
  function sleepRequests(appId) {
    if (!appId) return [];
    return inhibitors.filter(i => i.mode.startsWith("block")
        && (Shell.NiriMsg.appMatches(appId, i.name, "")
            || (i.appId && Shell.NiriMsg.appMatches(appId, i.appId, ""))));
  }
  function playbackStreams(appId) {
    if (!appId) return [];
    return streams.filter(s => s.kind === "playback" && s.muted !== true
        && Shell.NiriMsg.appMatches(appId, s.name, s.appId));
  }
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
