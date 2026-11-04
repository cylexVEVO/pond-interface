#!/usr/bin/env python3
"""Run session actions, using Pond's confirmed session lock before suspend."""
from pathlib import Path
import os
import signal
import subprocess
import sys
import time


INSTALLED = Path('/usr/share/pond-interface/lockscreen')
BUNDLE_ID = 'pond-pam-v2'


def lockscreen_candidates():
    """Prefer the lockscreen shipped beside this shell, then the system copy."""
    adjacent = Path(__file__).resolve().parents[2] / 'lockscreen'
    paths = []
    for path in (adjacent, INSTALLED):
        if path.is_dir() and path not in paths:
            paths.append(path)
    return paths


def is_current(path: Path) -> bool:
    # Fingerprint unlock needs the auth-only PAM templates next to Authentication.qml.
    return (path / 'session' / 'pam.d' / 'pond-password').is_file() and (
        path / 'session' / 'pam.d' / 'pond-fingerprint').is_file()


def bundle_token(path: Path) -> str:
    password = path / 'session' / 'pam.d' / 'pond-password'
    fingerprint = path / 'session' / 'pam.d' / 'pond-fingerprint'
    auth = path / 'session' / 'Authentication.qml'
    parts = [BUNDLE_ID, str(path)]
    for file in (password, fingerprint, auth):
        parts.append(str(file.stat().st_mtime_ns) if file.is_file() else '0')
    return ':'.join(parts)


def runtime_marker() -> Path:
    base = Path(os.environ.get('XDG_RUNTIME_DIR') or f'/tmp/pond-{os.getuid()}')
    base.mkdir(parents=True, exist_ok=True)
    return base / 'pond-lockscreen-bundle'


def ipc(path: Path, method: str) -> bool:
    result = subprocess.run(
        ['qs', '-p', str(path), 'ipc', 'call', 'lockscreen', method],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return result.returncode == 0


def stop_daemon(path: Path) -> None:
    # Lockscreen disables file watching, so an old process keeps stale unlock logic.
    pattern = f'qs -p {path}'
    try:
        listing = subprocess.run(
            ['pgrep', '-af', pattern], capture_output=True, text=True, check=False)
    except FileNotFoundError:
        return
    for line in listing.stdout.splitlines():
        parts = line.split(None, 1)
        if not parts:
            continue
        try:
            os.kill(int(parts[0]), signal.SIGTERM)
        except (ValueError, ProcessLookupError, PermissionError):
            pass


def run(action):
    if action in ('reboot', 'shutdown'):
        subprocess.run(['systemctl', 'reboot' if action == 'reboot' else 'poweroff'], check=True)
        return
    if action == 'reload-lockscreen':
        for path in lockscreen_candidates():
            stop_daemon(path)
        marker = runtime_marker()
        if marker.exists():
            marker.unlink()
        return
    if action not in ('lock', 'suspend'):
        raise ValueError('Unsupported session action')
    method = 'lock' if action == 'lock' else 'lockAndSuspend'
    paths = lockscreen_candidates()
    if not paths:
        raise RuntimeError('Pond lockscreen is not installed')

    # Only talk to a daemon that has the current PAM bundle. An older
    # /usr/share instance would otherwise keep serving the broken unlock path.
    current = [path for path in paths if is_current(path)]
    path = (current or paths)[0]
    token = bundle_token(path) if is_current(path) else ''
    marker = runtime_marker()
    stale = not token or marker.read_text().strip() != token if marker.exists() else bool(token)

    if stale:
        for candidate in paths:
            stop_daemon(candidate)
        time.sleep(0.15)
    elif current:
        for candidate in current:
            if ipc(candidate, method):
                return

    subprocess.run(['qs', '-d', '-p', str(path)], check=True)
    if token:
        marker.write_text(token)
    # Fresh daemons lock on startup; still poke IPC until the process is ready.
    for _ in range(30):
        if ipc(path, method):
            return
        time.sleep(0.1)
    if action == 'lock':
        return
    raise RuntimeError('Pond lockscreen did not start; refusing to suspend')


if __name__ == '__main__':
    run(sys.argv[1])
