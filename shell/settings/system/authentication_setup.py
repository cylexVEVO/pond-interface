#!/usr/bin/env python3
"""Switch known per-user Polkit agents to Pond; no elevated privileges needed."""
import os
from pathlib import Path
import subprocess
import sys

UNITS = ('hyprpolkitagent.service', 'plasma-polkit-agent.service',
         'polkit-gnome-authentication-agent-1.service', 'lxqt-policykit-agent.service')
DESKTOPS = ('polkit-gnome-authentication-agent-1.desktop',
            'polkit-kde-authentication-agent-1.desktop', 'lxqt-policykit-agent.desktop',
            'polkit-mate-authentication-agent-1.desktop')


def run(args):
    return subprocess.run(args, capture_output=True, text=True, timeout=15)


def main():
    # Restrict changes to known agent units and XDG per-user autostart overrides.
    config = Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config')
    roots = [config] + [Path(p) for p in os.environ.get('XDG_CONFIG_DIRS', '/etc/xdg').split(':') if p]
    for name in DESKTOPS:
        if not any((p / 'autostart' / name).exists() for p in roots):
            continue
        target = config / 'autostart' / name
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.is_symlink():
            raise RuntimeError(f'Cannot update symlink: {target}')
        if target.exists():
            backup = target.with_suffix('.desktop.pond-backup')
            if not backup.exists():
                backup.write_bytes(target.read_bytes())
        target.write_text('[Desktop Entry]\nType=Application\nName=Previous authentication agent\nHidden=true\n')
    for unit in UNITS:
        probe = run(['systemctl', '--user', 'show', unit, '--property=LoadState', '--value'])
        if probe.stdout.strip() != 'loaded':
            continue
        result = run(['systemctl', '--user', 'mask', '--now', unit])
        if result.returncode:
            raise RuntimeError(result.stderr.strip() or f'Could not disable {unit}')
    print('Setup saved. If the previous dialog is still active, sign out and back in. Agents started by custom compositor commands must be removed from that startup configuration.')


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f'Setup did not finish: {error}')
        sys.exit(1)
