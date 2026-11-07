# Sidebar reservation regression

This launches real Quickshell layer surfaces and foot clients in niri nested
inside a private, software-rendered Weston session. It does not touch the running
desktop. The shell harness imports the repository's `SidebarReservation.qml`.
It checks client positions and sizes, rather than only checking QML properties.

Tested with niri **26.04, 8ed0da44d974c32c6877d2f4630c314da0717ecb**,
Quickshell 0.3.0, Weston 16, and software rendering on Ubuntu 26.10.
Dependencies: `weston`, `quickshell` (`qs`), `foot`, Python 3, and the normal niri
Rust/native build dependencies. Qt's Wayland platform plugin is required.

## Build and run

In a disposable checkout of niri at the commit above, apply
`niri-test-telemetry.patch`. That patch exposes the tiled window's existing X
coordinate through IPC, because this niri version normally reports null. It does
not change layout behavior. Its Y coordinate is a placeholder; the test only uses X.

Build with `cargo build --no-default-features --bin niri`. This is a nested test
binary, not a replacement package for a desktop session. Save a copy for the
baseline, then apply `config/niri/patches/0001-preserve-view-relative-to-work-area.patch`
from Pond and rebuild.

From the Pond checkout:

```sh
python3 tests/zen-layout/run.py --niri /path/to/baseline-niri --report /tmp/baseline.json
python3 tests/zen-layout/run.py --niri /path/to/patched-niri --expect-fixed --report /tmp/two.json
python3 tests/zen-layout/run.py --niri /path/to/patched-niri --expect-fixed --windows 1 --report /tmp/one.json
python3 tests/zen-layout/run.py --niri /path/to/patched-niri --expect-fixed --windows 3 --focus-last --report /tmp/three.json
```

Without `--expect-fixed`, failures are reported without failing the command,
allowing the unpatched behavior to be recorded. The patched invocations must exit
zero. Logs are shown on failures, and private child processes are cleaned up.

## Results and scope

The original compositor failed six of the ten basic transitions: releasing the
reservation resized proportional columns but left their X position unchanged.
The patched compositor passed all 34 recorded states across the three scenarios,
including fullscreen entry/exit while changing reservation and rapid toggles.
Single windows remain centered; rightmost focused columns remain in the usable
area; repeated modes restore their widths. Expanded, collapsed, and Zen reserve
166, 58, and 0 logical pixels in this harness.

Do not use niri's internal headless backend for this integration test. Its empty
render-element state does not provide normal client frame delivery, which causes
misleading stale client widths and layer-surface commits. Weston plus niri's
nested backend exercises actual rendering and frame callbacks.

This is a compositor/layout integration test, not a full Pond UI test. Hardware
scanout, multiple monitors, fractional scaling, interactive gestures and animated
transitions still need desktop validation. Animations are disabled here to make
geometry assertions deterministic.
