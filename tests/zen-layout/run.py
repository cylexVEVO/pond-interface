#!/usr/bin/env python3
"""Real layer-shell regression. Requires niri built with niri-test-telemetry.patch."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--niri', required=True)
parser.add_argument('--expect-fixed', action='store_true')
parser.add_argument('--report', required=True)
parser.add_argument('--windows', type=int, default=2, choices=(1, 2, 3))
parser.add_argument('--focus-last', action='store_true')
args = parser.parse_args()
processes = []
report = []
with tempfile.TemporaryDirectory(prefix='pond-zen-layout-') as directory:
    work = Path(directory)
    runtime = work / 'runtime'
    runtime.mkdir(mode=0o700)
    env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime),
               QT_QPA_PLATFORM='wayland', QT_QUICK_BACKEND='software', LIBGL_ALWAYS_SOFTWARE='1')
    for key in ('DISPLAY', 'WAYLAND_DISPLAY', 'WAYLAND_SOCKET', 'NIRI_SOCKET'):
        env.pop(key, None)
    def start(command, name):
        log = open(work / (name + '.log'), 'w')
        process = subprocess.Popen(command, env=env, stdout=log, stderr=log)
        processes.append((process, log))
        return process
    def run(command):
        return subprocess.check_output(command, env=env, text=True, stderr=subprocess.PIPE, timeout=10).strip()
    def wait_for(callback):
        for _ in range(100):
            try:
                value = callback()
                if value:
                    return value
            except (subprocess.SubprocessError, OSError, ValueError):
                pass
            time.sleep(.1)
        raise RuntimeError('Timed out waiting for test compositor/client')
    def action(*command):
        return run([args.niri, 'msg', 'action', *command])
    def windows():
        return json.loads(run([args.niri, 'msg', '-j', 'windows']))
    def mode(value):
        run(['qs', '-p', str(work / 'shell.qml'), 'ipc', 'call', 'test', 'mode', value])
        time.sleep(.4)
        data = windows()
        record = dict(mode=value, windows=[dict(id=w['id'], x=w['layout']['tile_pos_in_workspace_view'][0],
                                              width=w['layout']['tile_size'][0],
                                              column=w['layout']['pos_in_scrolling_layout']) for w in data])
        report.append(record)
        return record
    try:
        (work / 'config.kdl').write_text('''layout {
 gaps 10
 center-focused-column "never"
 always-center-single-column
 default-column-width { proportion 0.5; }
 focus-ring { off; }
 border { off; }
}
animations { off; }
''')
        start(['weston', '--backend=headless', '--renderer=pixman', '--width=1920', '--height=1080', '--socket=pond-parent', '--idle-time=0', '--no-config'], 'weston')
        wait_for(lambda: (runtime / 'pond-parent').exists())
        env['WAYLAND_DISPLAY'] = 'pond-parent'
        start([args.niri, '-c', str(work / 'config.kdl')], 'niri')
        socket = wait_for(lambda: next(runtime.glob('niri.*.sock'), None))
        env['NIRI_SOCKET'] = str(socket)
        env['WAYLAND_DISPLAY'] = next(p.name for p in runtime.glob('wayland-*') if not p.name.endswith('.lock'))
        shutil.copy(ROOT / 'shell/SidebarReservation.qml', work)
        (work / 'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
PanelWindow {
 id: root
 property bool zen: false
 property bool expanded: true
 anchors { left: true; top: true; bottom: true }
 implicitWidth: 234
 exclusionMode: ExclusionMode.Ignore
 color: "transparent"
 mask: Region {}
 SidebarReservation { screen: root.screen; reservedWidth: root.zen ? 0 : root.expanded ? 166 : 58 }
 IpcHandler {
  target: "test"
  function mode(value: string) { if (value === "zen") root.zen = true; else {root.zen = false; root.expanded = value === "expanded";} }
  function ready(): bool { return true; }
 }
}
''')
        start(['qs', '-p', str(work / 'shell.qml')], 'qs')
        wait_for(lambda: run(['qs', '-p', str(work / 'shell.qml'), 'ipc', 'call', 'test', 'ready']) == 'true')
        for i in range(1, args.windows + 1):
            start(['foot', '-a', f'pond-zen-test-{i}', '-T', f'Test {i}', 'sleep', '120'], f'window{i}')
            wait_for(lambda: len(windows()) == i)
        first = (max if args.focus_last else min)(w['id'] for w in windows())
        action('focus-window', '--id', str(first))
        output = next(iter(json.loads(run([args.niri, 'msg', '-j', 'outputs'])).values()))
        output_width = output['logical']['width']
        expected_width = {}
        baseline_x = None
        failures = []
        for state in ['expanded', 'zen', 'expanded', 'collapsed', 'zen', 'collapsed', 'expanded', 'zen', 'collapsed', 'expanded']:
            record = mode(state)
            window = next(w for w in record['windows'] if w['id'] == first)
            if baseline_x is None:
                baseline_x = window['x']
            reserved = {'expanded': 166, 'collapsed': 58, 'zen': 0}[state]
            desired_x = baseline_x - (166 - reserved)
            if args.windows == 1:
                desired_x = reserved + (output_width - reserved - window['width']) / 2
            if args.focus_last:
                # A rightmost focused column may scroll further left to fit as it
                # grows. Require visibility, rather than imposing left alignment.
                if window['x'] < reserved or window['x'] + window['width'] > output_width:
                    failures.append(f"{state}: focused column is outside usable area")
            elif abs(window['x'] - desired_x) > 1:
                failures.append(f"{state}: x={window['x']}, expected {desired_x}")
            if state in expected_width and window['width'] != expected_width[state]:
                failures.append(f"{state}: width did not restore")
            expected_width[state] = window['width']
        if args.windows == 2 and not args.focus_last:
            mode('expanded')
            action('fullscreen-window')
            time.sleep(.4)
            fullscreen = mode('zen')
            window = next(w for w in fullscreen['windows'] if w['id'] == first)
            if abs(window['x']) > 1 or abs(window['width'] - output_width) > 1:
                failures.append('Zen changed fullscreen geometry')
            action('fullscreen-window')
            restored = mode('zen')
            window = next(w for w in restored['windows'] if w['id'] == first)
            if abs(window['x'] - (baseline_x - 166)) > 1:
                failures.append('Leaving fullscreen restored the stale sidebar gap')
            # Coalesce quick successive toggles, then verify the final reservation.
            for state in ['expanded', 'zen', 'collapsed', 'zen', 'expanded']:
                run(['qs', '-p', str(work / 'shell.qml'), 'ipc', 'call', 'test', 'mode', state])
            restored = mode('expanded')
            window = next(w for w in restored['windows'] if w['id'] == first)
            if abs(window['x'] - baseline_x) > 1 or window['width'] != expected_width['expanded']:
                failures.append('Rapid toggles failed to restore expanded layout')
        Path(args.report).write_text(json.dumps(dict(transitions=report, failures=failures), indent=2) + '\n')
        print('Transitions:', len(report), 'Failures:', len(failures))
        for failure in failures:
            print(failure)
        if args.expect_fixed and failures:
            raise SystemExit(1)
    except BaseException:
        for log in work.glob('*.log'):
            print(log.name, log.read_text()[-2000:])
        raise
    finally:
        for process, log in reversed(processes):
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
            log.close()
