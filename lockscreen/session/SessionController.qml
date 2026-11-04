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
        if (fingerprintAuthentication) fingerprintAuthentication.reset();
        authentication.fingerprintMode = false;
        phase = "authenticating";
        if (!authentication.authenticate(credential))
            reject();
    }

    function attemptFingerprint() {
        if (phase !== "editing" || !fingerprintAuthentication || !fingerprintAuthentication.pamReady) return;
        fingerprintAuthentication.authenticateFingerprint();
    }

    // Fingerprint scans run while the password field remains editable.
    Timer {
        interval: 100
        running: root.phase === "editing" && root.fingerprintAuthentication !== null
            && root.fingerprintAuthentication.pamReady
        onTriggered: root.attemptFingerprint()
    }

    function approve() {
        if (phase !== "editing" && phase !== "authenticating") return;
        phase = "approving";
        authentication.reset();
        if (fingerprintAuthentication) fingerprintAuthentication.reset();
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
        transition.active = false;
        frontend.active = false;
        frontend.currentText = "";
        authentication.reset();
        if (fingerprintAuthentication) fingerprintAuthentication.reset();
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
        function onSucceeded() {
            if (root.phase === "editing") root.approve();
        }
        // Reader timeouts and missing prints must not reject a typed password.
        function onAuthenticationError(message) { console.warn(message); }
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
