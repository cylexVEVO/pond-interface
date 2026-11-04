# Fingerprints

Install fprintd, its command-line tools, and your distribution's pam_fprintd
package. A supported libfprint reader is required. The daemon normally activates
on D-Bus demand. Keep the distribution's default fprintd PolicyKit policy.

The lock screen ships auth-only PAM services beside the session UI
(`lockscreen/session/pam.d/pond-password` and `pond-fingerprint`) and loads them
through Quickshell's `configDirectory` override. Password unlock never uses the
system `login`/`common-auth` stack, which often gains a fingerprint rule after
`libpam-fprintd` is installed and would wait for a finger after you type your
password. CMake still installs copies under `/etc/pam.d` for administrators.
Scans time out after 30 seconds and can be cancelled.

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

## Automatic setup

The Fingerprints page checks dependencies and PAM configuration on opening. On
Ubuntu, Debian, Arch Linux, and Fedora, **Set up fingerprint login** installs the
required distribution packages and configures Pond and an existing SDDM PAM
service. The system's polkit agent requests administrator authentication. Setup runs the helper bundled with the current shell through `pkexec`, so it
also works from a source checkout. No reinstall or separate helper installation
is needed. Python runs in isolated mode with administrator authentication; no
passwordless policy is installed. An absent pkexec disables setup.
No privileged commands are run on merely opening the page.

Setup keeps the original PAM files as `/etc/pam.d/*.pond-backup`, writes files
atomically, and preserves existing password, account, and session rules. It
refuses custom fingerprint configurations it cannot safely recognize. Package
installation failures leave PAM unchanged; retry setup after resolving the error.
Unsupported distributions need the manual setup above. Reader availability and
enrolled prints are checked using Refresh/Test after setup; successful software
setup does not imply compatible hardware. Do not close the shell during package
installation. To undo PAM changes, an administrator can restore the backups (or
remove the dedicated Pond PAM file if it had no predecessor).

Package references: [Ubuntu](https://packages.ubuntu.com/search?keywords=libpam-fprintd),
[Arch Linux](https://archlinux.org/packages/extra/x86_64/fprintd/),
[Fedora](https://packages.fedoraproject.org/pkgs/fprintd/fprintd-pam/index.html).

## Independent lock-screen authentication

Fingerprint scanning starts when the lock screen opens and retries after
timeouts or mismatches. The password field stays usable. Submitting a password
stops the scan; cancelling or failing a scan arms another one.

Password and fingerprint each use their own PamContext and auth-only policy
file, matching Quickshell's PAM guidance. Custom `POND_PAM_SERVICE` overrides
still load from `/etc/pam.d` for directory accounts or site policy. SDDM keeps
its own PAM conversation; setup only inserts a sufficient fingerprint line there.
