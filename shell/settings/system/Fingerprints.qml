import QtQuick
import Quickshell
import Quickshell.Io
import ".." as Settings
import "../../authentication" as Authentication
import "../.." as Shell

Settings.Modal {
    id: root
    title: "Fingerprints"
    closeLabel: "Back to System"
    bodyTop: 92
    property string probeError: ""
    property bool checkedSetup: false
    property bool detailsOpen: false
    property bool choosingFinger: false
    property string selectedFinger: "right-index-finger"
    property string action: ""
    property string notice: ""
    property int acceptedScans: 0
    property string scanState: ""
    property int scanSequence: 0
    function enrollmentLine(line) {
        output += line + "\n";
        if (action !== "enroll") return;
        try {
            const event = JSON.parse(line);
            if (event.kind === "log" || scanState === "complete" || scanState === "failed") return;
            scanState = event.kind;
            if (event.kind === "accepted") acceptedScans++;
            notice = event.message;
            scanSequence++;
        } catch (e) { /* Raw process errors remain available in Details. */ }
    }
    readonly property bool busy: operation.running || settingUp
    function fingerLabel(value) {
        const label = value.replace(/-/g, " ");
        return label.charAt(0).toUpperCase() + label.slice(1);
    }
    contentHeight: fields.height + 30
    property string output: ""
    property var setupState: ({ready: false, missing: [], canSetup: false})
    property bool settingUp: false
    property bool confirmDelete: false
    readonly property var fingers: ["left-thumb", "left-index-finger", "left-middle-finger", "left-ring-finger", "left-little-finger", "right-thumb", "right-index-finger", "right-middle-finger", "right-ring-finger", "right-little-finger"]
    function run(args) {
        if (operation.running) return;
        output = "";
        action = args[0];
        acceptedScans = 0;
        scanState = action === "enroll" ? "waiting" : "";
        scanSequence = 0;
        notice = action === "enroll" ? "Touch the reader. Lift your finger and repeat." : action === "verify" ? "Touch the reader." : "";
        confirmDelete = false;
        operation.command = ["python3", Quickshell.shellDir + "/settings/system/fingerprints.py"].concat(args);
        operation.running = true;
    }
    function cancel() { if (operation.running) { action = "cancel"; operation.signal(15); } }
    onBackRequested: { if (settingUp) return; if (choosingFinger) { choosingFinger = false; return; } cancel(); Settings.State.back(); }
    onEnabledChanged: if (!enabled && !Authentication.State.promptActive) cancel()
    Component.onCompleted: probe.running = true
    Component.onDestruction: cancel()
    Keys.onEscapePressed: { if (settingUp) return; if (choosingFinger) { choosingFinger = false; return; } cancel(); Settings.State.back(); }
    Process {
        id: operation
        stdout: SplitParser { onRead: data => root.enrollmentLine(data) }
        stderr: SplitParser { onRead: data => root.output += data + "\n" }
        onExited: (code, status) => {
            if (root.action === "cancel") root.notice = "Scan cancelled.";
            else if (root.action === "enroll") {
                if (root.scanState !== "complete" && root.scanState !== "failed") {
                    root.scanState = "failed";
                    root.notice = "Enrollment stopped before the fingerprint was saved. Try again.";
                }
            }
            else if (code !== 0) { root.notice = "Couldn’t finish. See details below."; }
            else if (root.action === "delete") root.notice = "Fingerprints removed.";
            else if (root.action === "verify") root.notice = "Scan finished. See details for the result.";
            else root.notice = "";
        }
    }
    Process {
        id: probe
        command: ["python3", Quickshell.shellDir + "/settings/system/fingerprint_setup.py", "status"]
        onRunningChanged: if (running) { root.probeError = ""; root.checkedSetup = false; }
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.setupState = JSON.parse(text); root.checkedSetup = true; }
                catch (e) {
                    root.checkedSetup = true;
                    root.setupState = {ready: false, canSetup: false, blocker: "Setup check returned an invalid response."};
                }
            }
        }
        stderr: SplitParser { onRead: data => root.probeError += data + "\n" }
        onExited: (code, status) => {
            root.checkedSetup = true;
            if (code !== 0) root.setupState = {ready: false, canSetup: false,
                blocker: "Couldn’t check setup: " + (root.probeError.trim() || "helper exited with code " + code)};
        }
    }
    Process {
        id: installer
        command: ["python3", Quickshell.shellDir + "/settings/system/fingerprint_setup.py", "launch"]
        stdout: SplitParser { onRead: data => root.output += data + "\n" }
        stderr: SplitParser { onRead: data => root.output += data + "\n" }
        onExited: (code, status) => {
            root.settingUp = false;
            root.notice = code === 0 ? "Ready to add a fingerprint."
                : code === 126 ? "Setup cancelled."
                : code === 127 ? "Couldn’t get administrator access."
                : "Setup didn’t finish.";
            if (code !== 0 && code !== 126) root.detailsOpen = true;
            probe.running = true;
        }
    }
    component Action: Rectangle {
        id: control
        property string text
        signal clicked
        implicitWidth: 160; implicitHeight: 42
        radius: 12
        color: hover.hovered || activeFocus ? Shell.PanelStyle.controlHover : Shell.Theme.colors.settingsRow
        opacity: enabled ? 1 : 0.4
        activeFocusOnTab: enabled
        Accessible.role: Accessible.Button
        Accessible.name: text
        Accessible.onPressAction: if (enabled) clicked()
        Keys.onReturnPressed: clicked()
        Keys.onSpacePressed: clicked()
        Text {
            anchors.centerIn: parent
            text: control.text; color: Shell.Theme.colors.text
            font.family: Shell.Theme.fontFamily; font.pixelSize: 14
        }
        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: control.clicked() }
    }
    component Copy: Text {
        width: fields.width
        wrapMode: Text.Wrap
        color: Shell.Theme.colors.text
        opacity: 0.65
        font.family: Shell.Theme.fontFamily
        font.pixelSize: 14
        lineHeight: 1.25
    }
    Column {
        id: fields
        x: 30; width: root.width - 60; spacing: 16
        Copy {
            text: !root.checkedSetup ? "Checking…"
                : root.setupState.ready ? "Use a fingerprint to log in and unlock."
                : root.settingUp ? "Setting up…"
                : root.setupState.canSetup ? "Set up fingerprint login first."
                : root.setupState.blocker || "Setup check returned no reason. Check again."
        }
        Action {
            visible: root.checkedSetup && !root.setupState.ready && root.setupState.canSetup
            width: fields.width
            text: root.settingUp ? "Setting up…" : "Set up"
            enabled: !root.busy
            onClicked: { root.output = ""; root.notice = ""; root.settingUp = true; installer.running = true; }
        }
        Copy {
            visible: !root.setupState.ready && root.setupState.canSetup
            text: "Requires administrator access."
        }
        Action {
            visible: root.checkedSetup && !root.setupState.ready && !root.setupState.canSetup
            text: "Check again"
            enabled: !probe.running
            onClicked: probe.running = true
        }
        Column {
            width: fields.width; spacing: 8
            visible: root.setupState.ready
            Settings.Field {
                id: fingerField
                width: parent.width
                title: "Finger"; value: root.fingerLabel(root.selectedFinger)
                enabled: !root.busy
                highlighted: root.choosingFinger
                onClicked: { root.choosingFinger = true; Qt.callLater(() => fingerMenu.forceActiveFocus()); }
            }
            Row {
                spacing: 8
                Action { width: (fields.width - 8) / 2; text: "Add fingerprint"; enabled: !root.busy; onClicked: root.run(["enroll", root.selectedFinger]) }
                Action { width: (fields.width - 8) / 2; text: "Test reader"; enabled: !root.busy; onClicked: root.run(["verify"]) }
            }
            Settings.Field {
                width: parent.width; title: "Saved fingerprints"; value: "View"; navigation: true
                enabled: !root.busy
                onClicked: { root.run(["list"]); root.detailsOpen = true; }
            }
        }
        Rectangle {
            visible: root.action === "enroll"
            width: fields.width; height: scanContent.height + 32; radius: 12
            color: Shell.Theme.colors.settingsRow
            border.width: 1
            border.color: root.scanState === "retry" || root.scanState === "failed" ? "#e6b06c" : Qt.alpha(Shell.PanelStyle.accent, 0.45)
            Column {
                id: scanContent
                x: 16; y: 16; width: parent.width - 32; spacing: 10
                Text {
                    text: root.scanState === "complete" ? "Fingerprint saved"
                        : root.scanState === "failed" ? "Enrollment stopped"
                        : root.acceptedScans === 0 ? "Scan your finger"
                        : root.acceptedScans + (root.acceptedScans === 1 ? " scan accepted" : " scans accepted")
                    color: Shell.Theme.colors.text
                    font.family: Shell.Theme.fontFamily; font.pixelSize: 16
                }
                Flow {
                    width: parent.width; spacing: 5
                    Repeater {
                        model: root.acceptedScans
                        Rectangle { width: 10; height: 10; radius: 5; color: Shell.PanelStyle.accent }
                    }
                }
                Copy {
                    width: parent.width; text: root.notice; opacity: 0.9
                    color: root.scanState === "retry" || root.scanState === "failed" ? "#e6b06c" : Shell.Theme.colors.text
                    Connections {
                        target: root
                        function onScanSequenceChanged() { scanPulse.restart(); }
                    }
                    SequentialAnimation on opacity {
                        id: scanPulse; running: false
                        NumberAnimation { to: 0.45; duration: 80 }
                        NumberAnimation { to: 0.9; duration: 160 }
                    }
                }
            }
        }
        Copy { visible: !!root.notice && root.action !== "enroll"; text: root.notice; opacity: 0.9 }
        Action { visible: operation.running; text: "Cancel"; onClicked: root.cancel() }
        Column {
            width: fields.width; spacing: 8
            visible: root.setupState.ready && !root.busy
            Settings.Field {
                width: parent.width; title: root.confirmDelete ? "Remove all saved fingerprints?" : "Remove fingerprints"
                value: root.confirmDelete ? "" : "All"
                onClicked: root.confirmDelete = true
            }
            Row {
                visible: root.confirmDelete; spacing: 8
                Action { text: "Remove all"; onClicked: root.run(["delete"]) }
                Action { text: "Keep them"; onClicked: root.confirmDelete = false }
            }
        }
        Settings.Field {
            visible: !!root.output
            width: parent.width; title: "Details"; value: root.detailsOpen ? "Hide" : "Show"
            onClicked: root.detailsOpen = !root.detailsOpen
        }
        Copy { visible: root.detailsOpen && !!root.output; text: root.output; font.pixelSize: 12 }
    }
    overlay: [
        MouseArea { anchors.fill: parent; visible: root.choosingFinger; onClicked: root.choosingFinger = false },
        Settings.Dropdown {
            id: fingerMenu
            visible: root.choosingFinger
            x: root.width - width - 30
            y: Math.max(20, Math.min(root.height - height - 20, fingerField.mapToItem(root, 0, fingerField.height).y))
            maximumHeight: Math.min(300, root.height - 40)
            options: root.fingers.map(finger => ({value: finger, label: root.fingerLabel(finger)}))
            currentValue: root.selectedFinger
            onDismissed: { root.choosingFinger = false; fingerField.forceActiveFocus(); }
            onSelected: value => { root.selectedFinger = value; root.choosingFinger = false; fingerField.forceActiveFocus(); }
        }
    ]
}
