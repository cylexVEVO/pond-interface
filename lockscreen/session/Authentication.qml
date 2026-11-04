import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam

AuthSession {
    id: root

    // Separate PamContext instances, each with an auth-only policy. Never use
    // system login/common-auth: after libpam-fprintd is installed that stack
    // often waits for a fingerprint while verifying a password.
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

    // Absolute path to the templates shipped beside this file. Relative
    // "pam.d" strings break when the lock screen daemon was started from a
    // different working directory than the QML tree.
    readonly property string bundledPamDirectory: {
        let path = Qt.resolvedUrl("pam.d").toString();
        if (path.startsWith("file://"))
            path = decodeURIComponent(path.substring(7));
        while (path.endsWith("/"))
            path = path.slice(0, -1);
        return path;
    }

    // Filled by resolvePam: /etc/pam.d when setup has written services, else bundle.
    property string pamConfigDirectory: bundledPamDirectory
    backend: nativePam
    successResult: PamResult.Success
    failedResult: PamResult.Failed
    maxTriesResult: PamResult.MaxTries

    Component.onCompleted: {
        if (!probePamService)
            return;
        if (!fingerprintOnly && Quickshell.env("POND_PAM_SERVICE")) {
            pamConfigDirectory = "/etc/pam.d";
            pamReady = true;
            return;
        }
        resolvePam.running = true;
    }

    Process {
        id: resolvePam
        // $1 = service name, $2 = bundled directory, $3 = require pam_fprintd (0/1)
        command: [
            "sh", "-c",
            "service=\"$1\"; bundled=\"$2\"; if [ \"$3\" = 1 ]; then "
            + "found=0; for base in /usr/lib /usr/lib64 /lib /lib64; do "
            + "for path in \"$base\"/security/pam_fprintd.so \"$base\"/*/security/pam_fprintd.so; do "
            + "[ -f \"$path\" ] && found=1 && break 2; done; done; "
            + "[ \"$found\" = 1 ] || exit 2; fi; "
            + "if [ -f \"/etc/pam.d/$service\" ]; then printf '%s\\n' /etc/pam.d; "
            + "elif [ -f \"$bundled/$service\" ]; then printf '%s\\n' \"$bundled\"; "
            + "else exit 1; fi",
            "pond-pam-resolve",
            root.fingerprintOnly ? "pond-fingerprint" : "pond-password",
            root.bundledPamDirectory,
            root.fingerprintOnly ? "1" : "0"
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                const directory = String(text || "").trim();
                if (directory.length > 0) {
                    root.pamConfigDirectory = directory;
                    root.pamReady = true;
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0)
                return;
            if (exitCode === 2)
                root.authenticationError("Fingerprint PAM module is not available");
            else
                root.authenticationError(root.fingerprintOnly
                    ? "Fingerprint unlock is not configured"
                    : "Password unlock is not configured");
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
