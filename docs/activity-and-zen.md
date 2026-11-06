# Activity details and Zen

Click the sidebar’s Mic / Rec / Audio / Awake / ··· indicator for **Why is this happening?**
The panel shows running PipeWire audio streams, app-reported names, and logind
sleep/idle requests with their reasons and modes. It provides app focus, default
microphone/output mute, media pause, sound controls, and lock/sleep settings.
Mute does not revoke recording permission. Media pause targets Pond’s selected
MPRIS player; app focus may fail for background services or unmatched app IDs.

**Super+Shift+Z** toggles Zen. This chord is unique in the shipped configuration
and appears in Settings → Keyboard shortcuts and the manual. Personal bindings
can override defaults; use the shortcut editor’s conflict detection when remapping.
The non-repeating binding bypasses app shortcut inhibitors, including after
remapping. Click the small × at the top left to exit without the keyboard.

Zen removes the sidebar’s reserved screen space and hides its clock, workspaces,
media, feedback and ordinary controls. Only exit, microphone/system-audio/uncertain capture (or unknown
capture status), and low battery signals remain. Notifications are still received
and saved according to their ordinary persistence rules, but their contents and
arrival surfaces remain hidden. They are not replayed on exit. Zen closes open
panels on entry. The previous expanded/collapsed preference stays intact.

Stay-awake is an optional session-only preference in activity details, off by
default. While Zen is active it temporarily removes Pond’s idle monitors for lock,
display-off and suspend. It does not alter the saved timeouts for either power
source. Exiting Zen, switching the option off, or restarting the shell restores
normal timer behavior; manual lock/suspend remain available. This is scoped to
Pond, not a system-wide inhibitor against other power managers or lid actions.

## Data limits

- A snapshot is refreshed every three seconds, with a refresh on panel opening.
- `pw-dump` exposes native and PulseAudio-compatible PipeWire streams. Only
  running audio streams are shown; a running stream is not proof of audible sound.
- Direct ALSA/BlueZ audio source links are labeled microphone. Sink monitors are
  labeled system audio; virtual, filtered or otherwise unidentifiable sources
  are labeled uncertain capture. App names are self-reported, browser tabs are
  not identified, and devices outside the visible PipeWire graph are unknown.
- `busctl --system --json=short … ListInhibitors` exposes logind requests. `delay`
  means a bounded postponement, including Pond’s lock-before-sleep safeguard;
  it is not an indefinite sleep blocker. `block` and `block-weak` remain distinct
  in the details. Compositor-only idle-inhibit protocol clients are not exposed
  by this implementation. Pond’s own configured idle timers are shown separately.
- Missing commands, service failures and invalid responses show unavailable
  status rather than an empty activity list. Neither query requires privilege
  escalation or terminates another application.

API references: [PipeWire pw-dump](https://docs.pipewire.org/page_man_pw-dump_1.html)
and [logind ListInhibitors](https://www.freedesktop.org/software/systemd/man/latest/org.freedesktop.login1.html).

Validation: `python3 -m unittest discover -s tests -p 'test_*.py'` and
`node --test tests/*.test.mjs`. Live visual and interaction checks require the
Pond Quickshell modules and a niri/Wayland session. Exercise recording, playback,
a logind sleep blocker, unavailable services, multi-output entry/exit, notification
arrival during Zen, and plugged-in/battery idle settings with stay-awake toggled.
