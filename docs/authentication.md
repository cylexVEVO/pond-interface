# Authentication dialog

The shell registers a native Polkit agent through Quickshell.Services.Polkit
(Quickshell 0.3.2 or newer with Polkit support). The dialog uses Pond's shared
theme, fields, and controls. Passwords go directly to the Polkit authentication
flow and are cleared on submission, prompt changes, and dismissal.

Only one Polkit agent can register per session. Disable the existing desktop
Polkit agent's autostart before restarting Pond; otherwise the existing agent
will continue to display its dialog. This repository does not manage external
agent services.

Manual validation in a graphical session:

- Trigger an authorized administrative action and check the complete request
  text, identity selection, password masking/reveal, and expandable action ID.
- Check incorrect-password retry, successful authentication, Cancel, and Escape.
- Check keyboard navigation, multiple queued requests, and all appearance themes.
- Check fingerprint or other PAM prompts if enabled on the machine.

The dialog requires a live Polkit service and Wayland session for integration
validation; it cannot be validated by a static QML check alone.

Fingerprint authentication is enabled by rerunning **Set up fingerprint login**
in Settings → System → Fingerprints. Setup adds the fingerprint PAM rule to
Polkit's existing policy, backing it up as /etc/pam.d/polkit-1.pond-backup.
Vendor policies in /usr/lib/pam.d or /usr/share/pam are copied into /etc/pam.d
when needed. Missing or custom fingerprint policies require manual review.
The existing password and account rules are retained. Polkit remains responsible
for authorization; the popup never approves requests using a separate scan.

With an enrolled finger, trigger a new administrative request and follow the
reader prompt. After three failed scans or the 30-second timeout, the existing
password flow takes over. Check successful scans, failed scans, password fallback,
cancellation during scanning, and switching identities on a machine with a reader.
