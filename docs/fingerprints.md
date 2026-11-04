# Fingerprints

Install fprintd, its command-line tools, and your distribution's pam_fprintd
package. A supported libfprint reader is required. The daemon normally activates
on D-Bus demand. Keep the distribution's default fprintd PolicyKit policy.

Install config/pam.d/pond-fingerprint as root-owned /etc/pam.d/pond-fingerprint
(mode 0644); the CMake install target includes it. The lock screen's fingerprint
button uses this dedicated PAM service. Password authentication continues to use
the existing PAM service. Scans time out after 30 seconds and can be cancelled.

For SDDM login, use your distribution's supported PAM configuration mechanism to
add `auth sufficient pam_fprintd.so max-tries=3 timeout=30` before password
authentication in /etc/pam.d/sddm. Preserve all existing account and session rules.
Pond deliberately does not overwrite the distribution's SDDM PAM stack. The
login button submits an empty credential to SDDM to initiate that PAM flow;
without this configuration it fails normally. SDDM serializes PAM authentication,
so wait for the scan timeout before retrying with a password. Fingerprint login
does not supply a password to unlock a password-encrypted keyring.

Open shell Settings > System > Fingerprints to list prints, select any of ten
fingers to enroll, test a scan, or remove all prints after confirmation. Output
from fprintd shows scan progress and errors. Closing the page cancels the running
tool and releases its D-Bus connection. To replace a print, enroll that finger
again. Removal currently removes all prints for the current account.

Authentication trusts PAM results only; the settings test tool never unlocks
anything. Account names for management are resolved from the real UID.

Hardware smoke test: enroll a finger, refresh the list, test both matching and
nonmatching fingers, cancel enrollment, lock and unlock with a fingerprint, cancel
a lock-screen scan and unlock with a password, and test SDDM login. Also verify
password fallback with the reader disconnected and fprintd unavailable.
