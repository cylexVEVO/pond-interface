import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import ".." as Settings
import "../.." as Shell

Settings.Modal {
    id: root
    title: "Fingerprints"
    contentHeight: fields.height + 30
    property string output: ""
    property bool confirmDelete: false
    readonly property var fingers: ["left-thumb", "left-index-finger", "left-middle-finger", "left-ring-finger", "left-little-finger", "right-thumb", "right-index-finger", "right-middle-finger", "right-ring-finger", "right-little-finger"]
    function run(args) {
        if (operation.running) return;
        output = "";
        confirmDelete = false;
        operation.command = ["python3", Quickshell.shellDir + "/settings/system/fingerprints.py"].concat(args);
        operation.running = true;
    }
    function cancel() { if (operation.running) operation.signal(15); }
    onBackRequested: { cancel(); Settings.State.back(); }
    onEnabledChanged: if (!enabled) cancel()
    Component.onCompleted: run(["list"])
    Component.onDestruction: cancel()
    Keys.onEscapePressed: { cancel(); Settings.State.back(); }
    Process {
        id: operation
        stdout: SplitParser { onRead: data => root.output += data + "\n" }
        stderr: SplitParser { onRead: data => root.output += data + "\n" }
        onExited: (code, status) => root.output += code === 0 ? "Done. Refresh to view enrolled prints.\n" : "Operation ended (" + code + "). Check that fprintd and a supported reader are available.\n"
    }
    Column {
        id: fields
        x: 30; width: root.width - 60; spacing: 12
        Text {
            width: parent.width; wrapMode: Text.Wrap
            color: Shell.Theme.colors.text
            text: "Choose a finger, then touch the reader repeatedly until enrollment completes. Fingerprints belong to your current account."
        }
        ComboBox { id: finger; width: parent.width; model: root.fingers; enabled: !operation.running }
        Row {
            spacing: 8
            Button { text: "Enroll"; enabled: !operation.running; onClicked: root.run(["enroll", finger.currentText]) }
            Button { text: "Refresh"; enabled: !operation.running; onClicked: root.run(["list"]) }
            Button { text: "Test"; enabled: !operation.running; onClicked: root.run(["verify"]) }
            Button { text: "Cancel"; enabled: operation.running; onClicked: root.cancel() }
        }
        Button {
            text: root.confirmDelete ? "Confirm removal of all fingerprints" : "Remove all fingerprints"
            enabled: !operation.running
            onClicked: { if (root.confirmDelete) root.run(["delete"]); else root.confirmDelete = true; }
        }
        Text { width: parent.width; text: root.output; wrapMode: Text.Wrap; color: Shell.Theme.colors.text }
    }
}
