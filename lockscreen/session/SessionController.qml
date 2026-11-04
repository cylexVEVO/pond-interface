import QtQuick

Item {
    id: root

    property var fingerprintAuthentication: null
    required property var authentication
    required property var transition
    required property var frontend
    property string phase: "editing"
    property bool transitionFailed: false

    signal releaseRequested
    signal finished

    function attemptUnlock(credential) {
        if (phase !== "editing")
            return;
        // Stop the fingerprint conversation before password PAM starts so the
        // reader is not held open during password verification.
        if (fingerprintAuthentication)
            fingerprintAuthentication.reset();
        fingerprintScan.stop();
        phase = "authenticating";
        if (!authentication.authenticate(credential))
            reject();
    }

    function attemptFingerprint() {
        if (phase !== "editing" || !fingerprintAuthentication || !fingerprintAuthentication.pamReady)
            return;
        if (fingerprintAuthentication.authenticationPending)
            return;
        // Abort can leave the backend busy for a tick; retry instead of giving up.
        if (!fingerprintAuthentication.authenticateFingerprint())
            fingerprintScan.restart();
    }

    function armFingerprintScan() {
        if (phase !== "editing" || !fingerprintAuthentication || !fingerprintAuthentication.pamReady)
            return;
        if (fingerprintAuthentication.authenticationPending)
            return;
        fingerprintScan.restart();
    }

    // Fingerprint scans run while the password field remains editable.
    Timer {
        id: fingerprintScan
        interval: 150
        onTriggered: root.attemptFingerprint()
    }

    onPhaseChanged: {
        if (phase === "editing")
            root.armFingerprintScan();
    }

    function approve() {
        if (phase !== "editing" && phase !== "authenticating")
            return;
        phase = "approving";
        fingerprintScan.stop();
        authentication.reset();
        if (fingerprintAuthentication)
            fingerprintAuthentication.reset();
        authentication.pamReady = false;
        transitionFailed = false;
        frontend.authenticationSucceeded();
        successDeadline.restart();
        transition.active = true;
    }

    function reject() {
        if (phase !== "authenticating")
            return;
        phase = "editing";
        frontend.authenticationFailed();
    }

    function tryHandoff() {
        if (phase !== "waiting")
            return;
        if (transitionFailed) {
            finish();
        } else if (transition.ready) {
            handoffDeadline.stop();
            phase = "exiting";
            frontend.active = false;
            releaseRequested();
            frontend.exitTransition.animationPaused = false;
        }
    }

    function finish() {
        // Only a successful authentication may release the lock, including fallbacks.
        if (!["approving", "waiting", "exiting"].includes(phase))
            return;
        const needsRelease = phase !== "exiting";
        phase = "finished";
        successDeadline.stop();
        handoffDeadline.stop();
        fingerprintScan.stop();
        transition.active = false;
        frontend.active = false;
        frontend.currentText = "";
        authentication.reset();
        if (fingerprintAuthentication)
            fingerprintAuthentication.reset();
        if (needsRelease)
            releaseRequested();
        finished();
    }

    function beginHandoff() {
        if (phase !== "approving")
            return;
        frontend.exitTransition.start();
        phase = "waiting";
        handoffDeadline.restart();
        tryHandoff();
    }

    Connections {
        target: root.frontend
        function onSubmitRequested(credential) { root.attemptUnlock(credential); }
        function onSuccessAnimationFinished() { root.beginHandoff(); }
        function onFinished() { root.finish(); }
    }
    Connections {
        target: root.authentication
        function onSucceeded() {
            if (root.phase !== "authenticating")
                return;
            root.approve();
        }
        function onRejected(result) { root.reject(); }
        function onAuthenticationError(message) {
            console.warn(message);
            root.reject();
        }
    }
    Connections {
        target: root.fingerprintAuthentication
        function onPamReadyChanged() {
            if (root.fingerprintAuthentication && root.fingerprintAuthentication.pamReady)
                root.armFingerprintScan();
        }
        function onSucceeded() {
            if (root.phase === "editing")
                root.approve();
        }
        function onRejected(result) {
            // Timeouts and mismatches leave password unlock available; retry scan.
            if (root.phase === "editing")
                root.armFingerprintScan();
        }
        // Missing module or abrupt abort must not reject a typed password.
        function onAuthenticationError(message) {
            console.warn(message);
            if (root.phase === "editing")
                root.armFingerprintScan();
        }
    }
    Connections {
        target: root.transition
        function onReadyChanged() { root.tryHandoff(); }
        function onFailed(reason) {
            console.warn(reason);
            root.transitionFailed = true;
            root.transition.active = false;
            if (root.phase === "waiting" || root.phase === "exiting")
                root.finish();
        }
    }
    Timer {
        id: handoffDeadline
        interval: 1000
        onTriggered: root.finish()
    }
    Timer {
        id: successDeadline
        // Bound the visual handoff after authentication, never an unanswered prompt.
        interval: 6500
        onTriggered: root.finish()
    }
}
