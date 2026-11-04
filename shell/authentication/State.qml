pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  id: root
  readonly property bool available: loader.status === Loader.Ready
  readonly property bool registered: available && loader.item.registered
  readonly property bool busy: setup.running
  property string notice: ""
  function retry() { loader.source = ""; loader.source = Qt.resolvedUrl("Agent.qml"); }
  function enable() {
    if (busy) return;
    notice = "";
    setup.running = true;
  }
  Loader { id: loader; source: Qt.resolvedUrl("Agent.qml") }
  Process {
    id: setup
    command: ["python3", Quickshell.shellDir + "/settings/system/authentication_setup.py"]
    stdout: StdioCollector { onStreamFinished: root.notice = text.trim() }
    stderr: StdioCollector { onStreamFinished: if (text.trim()) root.notice = text.trim() }
    onExited: (code, status) => { if (code === 0) root.retry(); }
  }
}
