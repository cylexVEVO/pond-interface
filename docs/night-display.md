# Night display

Open **Appearance → Night display** or **System → Display → Night display**.
Enable the switch and choose Manual, Custom times, or Sunset to sunrise.
Intensity ranges from neutral (0%) to 2000 K (100%). The setting affects all
connected displays, including applications, independently of the shell theme.

Custom times use the system's local 24-hour clock, with an inclusive start and
exclusive end. Both daytime and overnight intervals work. Equal endpoints are
rejected. The service rechecks wall-clock time every second, so resume and timezone
changes are picked up without reopening settings.

Sunset to sunrise requires latitude and longitude in decimal degrees. Coordinates
stay on the device. Solar elevation is computed locally: the display is neutral
with the sun above 3°, fully warm below −6° (civil dusk), and fades in between,
including polar day/night. Manual mode stays warm until disabled. Turning the
feature off or setting intensity to zero releases gamma control and restores
normal colors.

The service holds the gamma controls while warm and only uploads new ramps when
the target temperature changes. Switching between schedules that produce the same
warmth, or reselecting the active one, sends nothing to the compositor, and other
changes apply in place without a neutral frame in between. Newly connected
outputs are warmed automatically.

## Runtime requirements

Only Python 3 and Quickshell are needed. The service speaks the Wayland protocol
directly over `$WAYLAND_DISPLAY`, with no external night light tool. The compositor
and display driver must support `wlr-gamma-control-unstable-v1` (supported by Pond's Niri). Do not run another
gamma-control app alongside this feature. Missing dependencies and gamma failures
are reported on the settings page.

The shell starts one service at startup, independent of the settings window.
Settings are saved atomically in `$XDG_CONFIG_HOME/pond-interface/night-display.json`
(default `~/.config/pond-interface/night-display.json`). The service releases its
gamma controls on disable, stdin EOF, or SIGTERM; no background process is spawned.

## Verification

Run `python3 -m unittest discover -s tests -p 'test_night_display*.py' -v`.
On a real Niri session, verify warming at both ends of the
slider, disable/reset, a custom schedule crossing the current minute, solar mode
with local coordinates, shell restart, suspend/resume, and monitor hotplug.
