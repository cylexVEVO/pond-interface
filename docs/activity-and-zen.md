# Quiet activity signals and Zen

There is no activity dashboard or persistent launcher. Six-pixel capture lights
use the existing outer margin above the clock: orange for audio, green for known
camera capture, and a hollow blue-gray light for screen/unknown video capture.
Hover for app names and capture type. They do not take clicks from the clock.
In Zen the same lights sit centered beneath the exit control in an 8px row.
A failed capture query uses a hollow gray light with an unavailable tooltip,
never a microphone/camera-colored light or an extra control. Successful idle
queries add nothing.

A small amber ring on a workspace app icon indicates a matching logind sleep or
idle blocker. Hover the icon for its reason; clicking the icon still focuses its
window. Brief `delay` requests (including Pond's lock-before-sleep safeguard) do
not get marks. Weak blockers are described as conditional. A tiny speaker on the
app icon marks running, unmuted playback; existing sound and media controls stay
in their usual places.

**Super+Shift+Z** toggles Zen and is remappable under Keyboard shortcuts. The
manual reflects the current binding. Zen removes the sidebar's reserved space,
hides normal sidebar contents and notification surfaces immediately, and retains
only exit, capture dots and low battery. The previous sidebar layout is kept.
The visual surface stays an overlay; a separate input-transparent surface reserves
space in ordinary modes and unmaps in Zen. On niri 26.04 (`8ed0da4`), fully closing
the old gap also requires the [niri viewport patch](../config/niri/patches/README.md).
Without it, niri can preserve the old scroll position even after the reservation
has been released.
Notifications retain their ordinary history behavior and are not replayed on exit.

**Settings → System → Stay awake in Zen** is off by default and saved alongside
idle preferences. While Zen is active, it pauses Pond's automatic lock, display-off
and sleep timers without changing their values for either power source. Exit or
turn the option off to resume them. Manual lock/suspend remain available. This
option does not block lid actions or other power managers.

## Detection limits

Snapshots refresh every three seconds. App names are self-reported. Running
PipeWire streams do not prove audible output. Camera detection requires a visible
V4L2/libcamera upstream node; screen sharing and unknown video sources are labeled
separately. Direct device users outside PipeWire, browser tabs, virtual source
origins and compositor-only inhibitors may not be identifiable. No dot is not a
privacy guarantee. System settings report when capture detection is unavailable.
App badges require matching an app's name or process executable to a window's app
ID; unmatched background services and some sandboxed/portal requests cannot be
marked on an app icon. Badges describe the app and appear on all its windows;
they do not claim to identify a specific window. System settings also report
unavailable sleep-blocker detection.

The read-only query retains separate unavailable/error states rather than
reporting a failed query as an empty successful result. See
[PipeWire keys](https://docs.pipewire.org/devel/group__pw__keys.html) and
[logind](https://www.freedesktop.org/software/systemd/man/latest/org.freedesktop.login1.html).

Run `python3 -m unittest discover -s tests -p 'test_*.py'` and
`node --test tests/*.test.mjs`. Live UI validation needs Pond's Quickshell modules
and niri/Wayland. Check simultaneous microphone/camera dots, screen sharing,
blocked versus delayed sleep, app matching, settings persistence, both sidebar
sizes, and Zen notification privacy and restoration on all outputs.
