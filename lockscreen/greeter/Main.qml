pragma ComponentBehavior: Bound
import QtQuick
import QtQml.Models
import Pond.System
import "../frontend" as Frontend

Item {
    id: root
    property var loginBackend: sddm
    property var accountModel: userModel
    property var desktopModel: sessionModel
    property int userIndex: Math.max(0, accountModel.lastIndex)
    property int sessionIndex: Math.max(0, desktopModel.lastIndex)
    property int usersRevision: 0
    property int sessionsRevision: 0
    property bool requestPending: false
    property bool fingerprintAttempt: false
    property bool attemptAccepted: false
    property string queuedPassword: ""
    property string inFlightPassword: ""
    property int fastFingerprintFailures: 0
    property int ignoredLogins: 0
    readonly property var selectedUser: {
        usersRevision;
        return users.objectAt(userIndex);
    }
    readonly property var sessionNames: {
        sessionsRevision;
        return Array.from({length: desktops.count}, (_, index) => (desktops.objectAt(index) as Desktop)?.name || "");
    }

    function selectUser(direction) {
        if (!ui.acceptingInput || requestPending || users.count < 2)
            return;
        userIndex = (userIndex + direction + users.count) % users.count;
        ui.resetInput();
    }
    function selectSession(index) {
        if (!ui.acceptingInput || requestPending || index < 0 || index >= desktops.count)
            return;
        sessionIndex = index;
        ui.refocusRequested();
    }

    // SDDM runs one PAM conversation at a time, and pam_fprintd is first.
    // Start it immediately so a finger is enough. A password typed during
    // that scan is sent when the scan ends; a second login() while auth is
    // active is discarded by the daemon.
    function beginFingerprint() {
        if (!fingerprintLogin.ready || requestPending || ui.authenticationPending || queuedPassword.length || fastFingerprintFailures >= 3)
            return;
        if (!selectedUser || sessionIndex < 0 || sessionIndex >= desktops.count)
            return;
        fingerprintAttempt = true;
        attemptAccepted = false;
        inFlightPassword = "";
        requestPending = true;
        attemptWatch.restart();
        loginBackend.login(selectedUser.name, "", sessionIndex);
    }

    function beginPassword(credential) {
        fingerprintAttempt = false;
        attemptAccepted = false;
        queuedPassword = "";
        inFlightPassword = credential;
        requestPending = true;
        attemptWatch.restart();
        loginBackend.login(selectedUser.name, credential, sessionIndex);
    }

    component Account: QtObject {
        required property string name
        required property string realName
    }
    component Desktop: QtObject { required property string name }

    Instantiator {
        id: users
        model: root.accountModel
        delegate: Account {}
        onObjectAdded: root.usersRevision++
        onObjectRemoved: root.usersRevision++
    }
    Instantiator {
        id: desktops
        model: root.desktopModel
        delegate: Desktop {}
        onObjectAdded: root.sessionsRevision++
        onObjectRemoved: root.sessionsRevision++
    }
    NetworkStatus { id: network }
    FingerprintLogin {
        id: fingerprintLogin
        userName: root.selectedUser?.name || ""
    }
    QtObject {
        id: power
        function shutdown() {
            if (root.loginBackend.canPowerOff) root.loginBackend.powerOff();
        }
        function reboot() {
            if (root.loginBackend.canReboot) root.loginBackend.reboot();
        }
    }
    Frontend.Controller {
        id: ui
        powerBackend: power
        inputBlocked: !root.selectedUser || root.sessionIndex >= desktops.count
        onSubmitRequested: credential => {
            if (root.requestPending && root.fingerprintAttempt) {
                root.queuedPassword = credential;
                return;
            }
            root.beginPassword(credential);
        }
        onSuccessAnimationFinished: {
            exitTransition.animationPaused = false;
            exitTransition.start();
        }
        onFinished: active = false
    }
    Frontend.Screen {
        anchors.fill: parent
        controller: ui
        passwordTooltipVisible: root.accountModel.lastUser === ""
        displayName: root.selectedUser ? root.selectedUser.realName || root.selectedUser.name : ""
        multipleUsers: users.count > 1
        wifiConnected: network.wifiConnected
        compositors: root.sessionNames
        compositorIndex: root.sessionIndex
        onUserStepRequested: direction => root.selectUser(direction)
        onCompositorRequested: index => root.selectSession(index)
    }
    Timer {
        id: fingerprintArm
        interval: 400
        repeat: true
        running: fingerprintLogin.ready && !root.requestPending && !ui.authenticationPending && !root.queuedPassword.length
            && root.fastFingerprintFailures < 3 && !deferredPassword.running
        onTriggered: root.beginFingerprint()
    }
    // login() while the previous helper is still exiting never reaches PAM and
    // never answers. A real attempt emits an info message almost immediately.
    Timer {
        id: attemptWatch
        interval: 3000
        onTriggered: {
            if (!root.requestPending || root.attemptAccepted)
                return;
            root.ignoredLogins++;
            const password = root.inFlightPassword;
            root.requestPending = false;
            root.fingerprintAttempt = false;
            root.inFlightPassword = "";
            if (root.ignoredLogins >= 5) {
                root.fastFingerprintFailures = 3;
                if (password.length)
                    ui.authenticationFailed();
                return;
            }
            if (password.length)
                root.beginPassword(password);
        }
    }
    Timer {
        id: deferredPassword
        interval: 500
        property string password: ""
        onTriggered: root.beginPassword(password)
    }
    Connections {
        target: root.loginBackend
        function onInformationMessage() {
            root.attemptAccepted = true;
            root.ignoredLogins = 0;
        }
        function onLoginSucceeded() {
            root.queuedPassword = "";
            root.inFlightPassword = "";
            root.fingerprintAttempt = false;
            root.requestPending = false;
            attemptWatch.stop();
            deferredPassword.stop();
            ui.authenticationSucceeded();
        }
        function onLoginFailed() {
            if (!root.requestPending) return;
            const password = root.queuedPassword;
            const wasFingerprint = root.fingerprintAttempt;
            root.queuedPassword = "";
            root.inFlightPassword = "";
            root.fingerprintAttempt = false;
            root.requestPending = false;
            attemptWatch.stop();
            if (password.length) {
                deferredPassword.password = password;
                deferredPassword.restart();
                return;
            }
            if (!wasFingerprint) {
                ui.authenticationFailed();
                return;
            }
            // PAM info messages also occur for password failures; they do not
            // prove that a fingerprint scan happened. Bound unattended retries.
            root.fastFingerprintFailures++;
        }
        function onSocketDisconnected() {
            root.requestPending = false;
            root.fingerprintAttempt = false;
            root.queuedPassword = "";
            root.inFlightPassword = "";
            attemptWatch.stop();
            deferredPassword.stop();
            ui.active = false;
            ui.resetInput();
        }
    }
}
