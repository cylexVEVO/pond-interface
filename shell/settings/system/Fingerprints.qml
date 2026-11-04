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
    property string page: "list"
    property var savedFingers: []
    property bool listLoaded: false
    property string listError: ""
    readonly property bool scanning: page === "scan"
    readonly property bool scanDone: scanState === "complete" || scanState === "failed"
    readonly property color feedbackColor: scanState === "retry" || scanState === "failed" ? "#e6b06c" : Shell.PanelStyle.accent
    function refresh() { if (!inventory.running) inventory.running = true; }
    function finishScan() { page = "list"; notice = ""; refresh(); }
    function back() {
        if (settingUp) return;
        if (choosingFinger) { choosingFinger = false; return; }
        if (page !== "list") { const wasRunning = operation.running; cancel(); page = "list"; notice = ""; if (!wasRunning) refresh(); return; }
        cancel(); Settings.State.back();
    }
    property string probeError: ""
    property bool checkedSetup: false
    property bool detailsOpen: false
    property bool choosingFinger: false
    property string selectedFinger: "right-index-finger"
    property string action: ""
    property string notice: ""
    property bool operationError: false
    property int acceptedScans: 0
    property string scanState: ""
    property int scanSequence: 0
    function enrollmentLine(line) {
        if (action !== "enroll" && action !== "verify") { output += line + "\n"; return; }
        try {
            const event = JSON.parse(line);
            output = (output + event.message + "\n").slice(-6000);
            if (event.kind === "log" || scanState === "complete" || scanState === "failed") return;
            scanState = event.kind;
            operationError = event.kind === "failed";
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
        detailsOpen = false;
        operationError = false;
        action = args[0];
        acceptedScans = 0;
        scanState = action === "enroll" ? "waiting" : "";
        scanSequence = 0;
        notice = action === "enroll" ? "Touch the reader. Lift your finger and repeat." : action === "verify" ? "Touch the reader." : "";
        confirmDelete = false;
        operation.command = ["python3", Quickshell.shellDir + "/settings/system/fingerprints.py"].concat(args);
        if (action === "enroll") page = "scan";
        operation.running = true;
    }
    function cancel() { if (operation.running) { action = "cancel"; operation.signal(15); } }
    onBackRequested: back()
    onEnabledChanged: if (!enabled && !Authentication.State.promptActive) cancel()
    Component.onCompleted: probe.running = true
    Component.onDestruction: cancel()
    Keys.onEscapePressed: back()
    Process {
        id: inventory
        command: ["python3", Quickshell.shellDir + "/settings/system/fingerprints.py", "list"]
        onRunningChanged: if (running) root.listError = ""
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    root.savedFingers = result.fingers || [];
                    root.listError = result.error || "";
                    root.listLoaded = true;
                } catch (e) { root.listError = "Couldn’t read saved fingerprints."; }
            }
        }
        stderr: SplitParser { onRead: data => root.listError = data }
        onExited: (code, status) => {
            root.listLoaded = true;
            if (code !== 0 && !root.listError) root.listError = "Couldn’t read saved fingerprints.";
        }
    }
    Process {
        id: operation
        stdout: SplitParser { onRead: data => root.enrollmentLine(data) }
        stderr: SplitParser { onRead: data => root.output += data + "\n" }
        onExited: (code, status) => {
            if (root.action === "cancel") { root.notice = "Scan cancelled."; root.refresh(); }
            else if (root.action === "enroll") {
                if (root.scanState !== "complete" && root.scanState !== "failed") {
                    root.scanState = "failed";
                    root.operationError = true;
                    root.notice = "Enrollment stopped before the fingerprint was saved. Try again.";
                }
            }
            else if (code !== 0) { root.operationError = true; if (root.scanState !== "failed") root.notice = "Couldn’t finish. Try again."; }
            else if (root.action === "delete") { root.notice = "Fingerprints removed."; root.refresh(); }
            else if (root.action === "verify") {
                if (root.scanState !== "complete" && root.scanState !== "failed") { root.operationError = true; root.notice = "No fingerprint was recognized."; }
            }
            else root.notice = "";
        }
    }
    Process {
        id: probe
        command: ["python3", Quickshell.shellDir + "/settings/system/fingerprint_setup.py", "status"]
        onRunningChanged: if (running) { root.probeError = ""; root.checkedSetup = false; }
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.setupState = JSON.parse(text); root.checkedSetup = true; if (root.setupState.ready) root.refresh(); }
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
            root.operationError = code !== 0 && code !== 126;
            probe.running = true;
        }
    }
    component Action: Rectangle {
        id: control
        property string text
        property bool primary: false
        signal clicked
        implicitWidth: 160; implicitHeight: 42
        radius: 12
        color: primary ? Qt.alpha(Shell.PanelStyle.accent, hover.hovered || activeFocus ? 0.32 : 0.2) : hover.hovered || activeFocus ? Shell.PanelStyle.controlHover : Shell.Theme.colors.settingsRow
        border.width: activeFocus ? 1 : 0
        border.color: Shell.PanelStyle.accent
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
        x: 30; width: root.width - 60; spacing: 20
        Column {
            width: parent.width; spacing: 16
            visible: !root.setupState.ready
            Copy {
                text: !root.checkedSetup ? "Checking fingerprint support…" : root.settingUp ? "Setting up fingerprint login…"
                    : root.setupState.canSetup ? "Enable fingerprint login on this computer."
                    : root.setupState.blocker || "Couldn’t check setup. Try again."
            }
            Action {
                width: parent.width; primary: true
                text: root.setupState.canSetup ? "Set up fingerprint login" : "Check again"
                enabled: root.checkedSetup && !root.busy && !probe.running
                onClicked: {
                    if (!root.setupState.canSetup) { probe.running = true; return; }
                    root.output = ""; root.notice = ""; root.detailsOpen = false; root.settingUp = true; installer.running = true;
                }
            }
            Copy { visible: root.setupState.canSetup; text: "You’ll be asked for your administrator password."; font.pixelSize: 12 }
        }
        Column {
            width: parent.width; spacing: 16
            visible: root.setupState.ready && root.page === "list"
            Copy { text: "Log in and unlock with a touch." }
            Rectangle {
                visible: root.savedFingers.length === 0
                width: parent.width; height: 126; radius: 16
                color: Shell.Theme.colors.settingsRow
                Column {
                    anchors.centerIn: parent; spacing: 8; width: parent.width - 40
                    Copy { width: parent.width; horizontalAlignment: Text.AlignHCenter; opacity: 1; font.pixelSize: 16; text: inventory.running ? "Loading fingerprints…" : root.listError ? "Reader unavailable" : "No fingerprints yet" }
                    Copy { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: root.listError ? "Check the reader and try again." : "Add a finger to get started." }
                }
            }
            Column {
                width: parent.width; spacing: 6
                Repeater {
                    model: root.savedFingers
                    Rectangle {
                        required property string modelData
                        width: fields.width; height: 64; radius: 12
                        color: Shell.Theme.colors.settingsRow
                        Image { x: 18; anchors.verticalCenter: parent.verticalCenter; width: 28; height: 32; source: "fingerprint.svg" }
                        Text { x: 62; anchors.verticalCenter: parent.verticalCenter; text: root.fingerLabel(parent.modelData); color: Shell.Theme.colors.text; font.family: Shell.Theme.fontFamily; font.pixelSize: 15 }
                        Text { anchors.right: parent.right; anchors.rightMargin: 20; anchors.verticalCenter: parent.verticalCenter; text: "Saved"; color: Shell.Theme.colors.text; opacity: 0.45; font.family: Shell.Theme.fontFamily; font.pixelSize: 12 }
                    }
                }
            }
            Action {
                width: parent.width; primary: true; text: "Add fingerprint"
                enabled: !root.busy && !inventory.running && root.savedFingers.length < 10
                onClicked: { root.selectedFinger = root.fingers.find(f => !root.savedFingers.includes(f)) || root.fingers[0]; root.page = "choose"; root.notice = ""; root.detailsOpen = false; }
            }
            Row {
                visible: root.savedFingers.length > 0 && !root.confirmDelete; spacing: 8
                Action { width: (fields.width - 8) / 2; text: "Test fingerprint"; enabled: !root.busy; onClicked: root.run(["verify"]) }
                Action { width: (fields.width - 8) / 2; text: "Remove all…"; enabled: !root.busy; onClicked: root.confirmDelete = true }
            }
            Column {
                visible: root.confirmDelete; width: parent.width; spacing: 12
                Copy { text: "Remove all saved fingerprints? You can still use your password." }
                Row {
                    spacing: 8
                    Action { text: "Keep fingerprints"; onClicked: root.confirmDelete = false }
                    Action { text: "Remove all"; enabled: !root.busy; onClicked: root.run(["delete"]) }
                }
            }
            Copy { visible: !!root.listError; text: root.listError }
            Action { visible: !!root.listError; text: "Try again"; enabled: !inventory.running; onClicked: root.refresh() }
        }
        Column {
            visible: root.page === "choose"; width: parent.width; spacing: 20
            Copy { text: "Choose a finger you haven’t added yet." }
            Settings.Field {
                id: fingerField
                width: parent.width; title: "Finger"; value: root.fingerLabel(root.selectedFinger)
                highlighted: root.choosingFinger
                onClicked: { root.choosingFinger = true; Qt.callLater(() => fingerMenu.forceActiveFocus()); }
            }
            Row {
                spacing: 8
                Action { width: (fields.width - 8) / 2; text: "Back"; onClicked: root.back() }
                Action { width: (fields.width - 8) / 2; primary: true; text: "Start scanning"; enabled: !root.busy && !inventory.running; onClicked: root.run(["enroll", root.selectedFinger]) }
            }
        }
        Column {
            visible: root.scanning; width: parent.width; spacing: 24
            Item {
                width: parent.width; height: 144
                Rectangle {
                    anchors.centerIn: parent; width: 128; height: 128; radius: 64
                    color: Qt.alpha(root.feedbackColor, 0.08)
                    border.width: 1; border.color: Qt.alpha(root.feedbackColor, 0.3)
                    Image { anchors.centerIn: parent; width: 64; height: 76; source: "fingerprint.svg" }
                    SequentialAnimation on opacity {
                        running: root.scanning && operation.running && !root.scanDone
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.55; duration: 1000 }
                        NumberAnimation { to: 1; duration: 1000 }

                    }
                }
            }
            Column {
                width: parent.width; spacing: 10
                Copy { horizontalAlignment: Text.AlignHCenter; opacity: 1; font.pixelSize: 20; text: root.scanState === "complete" ? "Fingerprint added" : root.scanState === "failed" ? "Enrollment failed" : root.fingerLabel(root.selectedFinger) }
                Copy { height: 48; horizontalAlignment: Text.AlignHCenter; text: root.scanState === "complete" ? "You can now use this finger to log in." : root.notice; color: root.feedbackColor; opacity: 1 }
                Copy { horizontalAlignment: Text.AlignHCenter; font.pixelSize: 12; text: root.scanDone ? "" : root.acceptedScans ? root.acceptedScans + (root.acceptedScans === 1 ? " good scan" : " good scans") + " · Keep going" : "Waiting for the first scan" }
            }
            Row {
                spacing: 8; anchors.horizontalCenter: parent.horizontalCenter
                Action { visible: !root.scanDone; text: "Cancel"; onClicked: root.back() }
                Action { visible: root.scanState === "failed"; text: "Back"; enabled: !operation.running; onClicked: root.finishScan() }
                Action { visible: root.scanDone; primary: true; text: root.scanState === "complete" ? "Done" : "Try again"; enabled: !operation.running; onClicked: root.scanState === "complete" ? root.finishScan() : root.run(["enroll", root.selectedFinger]) }
            }
        }
        Copy { visible: !!root.notice && !root.scanning; text: root.notice; opacity: 0.9 }
        Action { visible: operation.running && !root.scanning; text: "Cancel"; onClicked: root.cancel() }
        Action {
            visible: !!root.output && root.operationError
            text: root.detailsOpen ? "Hide error details" : "Error details"
            onClicked: root.detailsOpen = !root.detailsOpen
        }
        Copy { visible: root.detailsOpen && root.operationError && !operation.running; text: root.output; font.pixelSize: 12; maximumLineCount: 6; elide: Text.ElideRight }
    }
    overlay: [
        MouseArea { anchors.fill: parent; visible: root.choosingFinger; onClicked: root.choosingFinger = false },
        Settings.Dropdown {
            id: fingerMenu
            visible: root.choosingFinger
            x: root.width - width - 30
            y: Math.max(20, Math.min(root.height - height - 20, fingerField.mapToItem(root, 0, fingerField.height).y))
            maximumHeight: Math.min(300, root.height - 40)
            options: root.fingers.map(finger => ({value: finger, label: root.fingerLabel(finger), disabled: root.savedFingers.includes(finger)}))
            currentValue: root.selectedFinger
            onDismissed: { root.choosingFinger = false; fingerField.forceActiveFocus(); }
            onSelected: value => { root.selectedFinger = value; root.choosingFinger = false; fingerField.forceActiveFocus(); }
        }
    ]
}
