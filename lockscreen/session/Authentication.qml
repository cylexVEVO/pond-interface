import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam

AuthSession {
    id: root

    // Separate PamContext instances use these auth-only configs. Never fall
    // through to system login/common-auth: after libpam-fprintd is installed
    // that stack often waits for a fingerprint during a password unlock.
    property bool fingerprintOnly: false
    function authenticateFingerprint() {
        if (authenticationPending)
            return false;
        return authenticate("", true);
    }

    property bool probePamService: true
    property string pamConfig: fingerprintOnly
        ? "pond-fingerprint"
        : (Quickshell.env("POND_PAM_SERVICE") || "pond-password")

    // Bundled beside this file so unlock works without rewriting /etc/pam.d.
    // Custom POND_PAM_SERVICE overrides still load from the system directory.
    readonly property string pamConfigDirectory: fingerprintOnly || !Quickshell.env("POND_PAM_SERVICE")
        ? "pam.d"
        : "/etc/pam.d"
    backend: nativePam
    successResult: PamResult.Success
    failedResult: PamResult.Failed
    maxTriesResult: PamResult.MaxTries

    Component.onCompleted: {
        if (!probePamService)
            return;
        if (fingerprintOnly)
            detectFingerprintProc.running = true;
        else
            pamReady = true;
    }

    Process {
        id: detectFingerprintProc
        // Fingerprint unlock needs the PAM module; configs ship with the lock screen.
        command: ["sh", "-c", "for base in /usr/lib /usr/lib64 /lib /lib64; do for path in \"$base\"/security/pam_fprintd.so \"$base\"/*/security/pam_fprintd.so; do [ -f \"$path\" ] && exit 0; done; done; exit 1"]

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0)
                root.pamReady = true;
            else
                root.authenticationError("Fingerprint PAM module is not available");
        }
    }

    PamContext {
        id: nativePam
        configDirectory: root.pamConfigDirectory
        config: root.pamConfig
        // An empty user makes PamContext resolve getuid() itself. Avoid trusting
        // a mutable environment variable for the authentication identity.
        user: ""
    }
}
