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
    property var setupState: ({ready: false, missing: [], canSetup: false})
    property bool settingUp: false
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
    onBackRequested: { if (settingUp) return; cancel(); Settings.State.back(); }
    onEnabledChanged: if (!enabled) cancel()
    Component.onCompleted: probe.running = true
    Component.onDestruction: cancel()
    Keys.onEscapePressed: { if (settingUp) return; cancel(); Settings.State.back(); }
    Process {
        id: operation
        stdout: SplitParser { onRead: data => root.output += data + "\n" }
        stderr: SplitParser { onRead: data => root.output += data + "\n" }
        onExited: (code, status) => root.output += code === 0 ? "Done. Refresh to view enrolled prints.\n" : "Operation ended (" + code + "). Check that fprintd and a supported reader are available.\n"
    }
    Process {
        id: probe
        command: ["python3", Quickshell.shellDir + "/settings/system/fingerprint_setup.py", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.setupState = JSON.parse(text); }
                catch (e) { root.output += "Unable to check fingerprint setup.\n"; }
            }
        }
        stderr: SplitParser { onRead: data => root.output += data + "\n" }
    }
    Process {
        id: installer
        command: ["pkexec", "/usr/libexec/pond-fingerprint-setup", "setup"]
        stdout: SplitParser { onRead: data => root.output += data + "\n" }
        stderr: SplitParser { onRead: data => root.output += data + "\n" }
        onExited: (code, status) => {
            root.settingUp = false;
            if (code !== 0) root.output += "Setup was cancelled or failed. You can retry.\n";
            probe.running = true;
        }
    }
    Column {
        id: fields
        x: 30; width: root.width - 60; spacing: 12
        Text {
            width: parent.width; wrapMode: Text.Wrap; color: Shell.Theme.colors.text
            text: root.setupState.ready ? "Fingerprint support is configured. Refresh to view enrolled prints."
                : "Setup needed: " + root.setupState.missing.join(", ") + "\nSetup installs packages and configures login and unlock. Your system will ask for administrator authentication."
        }
        Button {
            visible: !root.setupState.ready
            text: root.settingUp ? "Setting up…" : "Set up fingerprint login"
            enabled: root.setupState.canSetup && !root.settingUp && !operation.running
            onClicked: { root.output = ""; root.settingUp = true; installer.running = true; }
        }
        Text {
            visible: !root.setupState.ready && !root.setupState.canSetup
            width: parent.width; wrapMode: Text.Wrap; color: Shell.Theme.colors.text
            text: "Automatic setup requires the installed Pond setup helper, polkit, and Ubuntu, Debian, Arch Linux or Fedora."
        }
        Text {
            width: parent.width; wrapMode: Text.Wrap
            color: Shell.Theme.colors.text
            text: "Choose a finger, then touch the reader repeatedly until enrollment completes. Fingerprints belong to your current account."
        }
        ComboBox { id: finger; width: parent.width; model: root.fingers; enabled: !operation.running && !root.settingUp && root.setupState.ready }
        Row {
            spacing: 8
            Button { text: "Enroll"; enabled: !operation.running && !root.settingUp && root.setupState.ready; onClicked: root.run(["enroll", finger.currentText]) }
            Button { text: "Refresh"; enabled: !operation.running && !root.settingUp && root.setupState.ready; onClicked: root.run(["list"]) }
            Button { text: "Test"; enabled: !operation.running && !root.settingUp && root.setupState.ready; onClicked: root.run(["verify"]) }
            Button { text: "Cancel"; enabled: operation.running; onClicked: root.cancel() }
        }
        Button {
            text: root.confirmDelete ? "Confirm removal of all fingerprints" : "Remove all fingerprints"
            enabled: !operation.running && !root.settingUp && root.setupState.ready
            onClicked: { if (root.confirmDelete) root.run(["delete"]); else root.confirmDelete = true; }
        }
        Text { width: parent.width; text: root.output; wrapMode: Text.Wrap; color: Shell.Theme.colors.text }
    }
}
