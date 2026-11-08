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
stay on the device. `wlsunset` computes solar transitions locally, including polar
day/night, and handles newly connected outputs. Manual mode stays warm until
disabled. Turning the feature off or setting intensity to zero releases gamma
control and restores normal colors.

## Runtime requirements

Install **wlsunset** in the desktop image (Arch package: `wlsunset`) alongside
Python 3 and Quickshell. The compositor and display driver must support
`wlr-gamma-control-unstable-v1` (supported by Pond's Niri). Do not run another
gamma-control app alongside this feature. Missing dependencies and gamma failures
are reported on the settings page. This repository does not contain the desktop
image's package manifest; its packaging must include the runtime dependency.

The shell starts one service at startup, independent of the settings window.
Settings are saved atomically in `$XDG_CONFIG_HOME/pond-interface/night-display.json`
(default `~/.config/pond-interface/night-display.json`). The service owns only its
own `wlsunset` child and stops it on disable, reconfiguration, stdin EOF, or SIGTERM.
No global process killing or detached background process is used.

## Verification

Run `python3 -m unittest discover -s tests -p 'test_night_display*.py' -v`.
On a real Niri session with wlsunset installed, verify warming at both ends of the
slider, disable/reset, a custom schedule crossing the current minute, solar mode
with local coordinates, shell restart, suspend/resume, and monitor hotplug.
