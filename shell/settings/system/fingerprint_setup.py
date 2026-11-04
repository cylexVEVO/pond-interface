#!/usr/bin/python3 -I
"""Fixed-purpose privileged setup. No caller-controlled commands or paths."""
import json
import os
import platform
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

PAM = Path('/etc/pam.d')
LOCK = 'auth required pam_fprintd.so max-tries=3 timeout=30\naccount required pam_unix.so\n'
PASSWORD = 'auth required pam_unix.so\naccount required pam_unix.so\n'
LOGIN = 'auth sufficient pam_fprintd.so max-tries=3 timeout=30\n'


def distribution():
    return platform.freedesktop_os_release()


def packages():
    release = distribution()
    recipes = {
        'ubuntu': ['/usr/bin/apt-get', 'install', '-y', 'fprintd', 'libpam-fprintd'],
        'debian': ['/usr/bin/apt-get', 'install', '-y', 'fprintd', 'libpam-fprintd'],
        'arch': ['/usr/bin/pacman', '-S', '--needed', '--noconfirm', 'fprintd'],
        'fedora': ['/usr/bin/dnf', 'install', '-y', 'fprintd', 'fprintd-pam'],
    }
    for family in [release.get('ID', ''), *release.get('ID_LIKE', '').split()]:
        if family in recipes:
            return recipes[family]
    return None


def login_config(text):
    if any('pam_fprintd.so' in line.split('#', 1)[0] for line in text.splitlines()):
        raise ValueError('SDDM already has custom fingerprint rules; review them manually.')
    # Preserve initial security checks; insert before the first ordinary auth rule.
    lines = text.splitlines(keepends=True)
    for i, line in enumerate(lines):
        words = line.split()
        if words and words[0] in ('auth', '@include'):
            if 'pam_nologin.so' in line or 'pam_shells.so' in line:
                continue
            lines.insert(i, LOGIN)
            return ''.join(lines)
    raise ValueError('Unrecognized SDDM PAM configuration; no changes made.')


def read(path):
    if path.is_symlink():
        raise ValueError(f'Refusing to replace symlink: {path}')
    return path.read_text() if path.exists() else ''


def status():
    missing = []
    if not all(shutil.which('fprintd-' + name) for name in ('list', 'enroll', 'delete', 'verify')):
        missing.append('fprintd tools')
    if not any(list(Path(base).glob(pattern)) for base in ('/usr/lib', '/usr/lib64', '/lib', '/lib64')
               for pattern in ('security/pam_fprintd.so', '*/security/pam_fprintd.so')):
        missing.append('PAM fingerprint module')
    if read(PAM / 'pond-fingerprint') != LOCK:
        missing.append('lock screen configuration')
    if read(PAM / 'pond-password') != PASSWORD:
        missing.append('password unlock configuration')
    sddm = read(PAM / 'sddm')
    if sddm and LOGIN not in sddm.splitlines(keepends=True):
        missing.append('SDDM configuration')
    release = distribution()
    system = release.get('PRETTY_NAME', release.get('ID', 'Unknown Linux distribution'))
    command = packages()
    blockers = []
    if not command:
        blockers.append(f"No package installer is configured for {system} (ID: {release.get('ID', 'unknown')}; family: {release.get('ID_LIKE', 'not declared')}).")
    elif not Path(command[0]).is_file():
        blockers.append(f'{system} needs {command[0]} for setup, but it is missing.')
    if not Path('/usr/bin/pkexec').is_file():
        blockers.append('pkexec is missing. Install your distribution’s polkit package to allow administrator authentication.')
    return {'ready': not missing, 'missing': missing, 'blocker': '\n\n'.join(blockers),
            'system': system, 'canSetup': not blockers, 'sddm': bool(sddm)}


def launch_command():
    # Use the helper shipped beside the running shell, including source checkouts.
    # pkexec still requires full administrator authorization; no permissive policy
    # or persistent elevation is installed. Isolated Python ignores user imports.
    return ['/usr/bin/pkexec', '/usr/bin/python3', '-I', '-u',
            str(Path(__file__).resolve()), 'setup']


def atomic_write(path, text):
    fd, temporary = tempfile.mkstemp(prefix='.pond-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write(text)
            stream.flush()
            os.fchmod(stream.fileno(), 0o644)
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def setup():
    if os.geteuid() != 0:
        raise PermissionError('Administrator authentication is required.')
    command = packages()
    if not command:
        raise ValueError('Automatic setup is not supported on this distribution.')
    old_password = read(PAM / 'pond-password')
    old_lock = read(PAM / 'pond-fingerprint')
    old_login = read(PAM / 'sddm')
    new_login = old_login if not old_login or LOGIN in old_login.splitlines(keepends=True) else login_config(old_login)
    # Validate all files before package installation or PAM changes.
    for name, old in (('pond-fingerprint', old_lock), ('pond-password', old_password), ('sddm', old_login)):
        backup = PAM / (name + '.pond-backup')
        if old and not backup.exists():
            read(backup)
            with backup.open('x') as stream:
                stream.write(old)
    print('Installing fingerprint support…', flush=True)
    subprocess.run(command, check=True, env={'PATH': '/usr/sbin:/usr/bin:/sbin:/bin', 'DEBIAN_FRONTEND': 'noninteractive', 'LC_ALL': 'C'})
    # A package manager may have modified PAM; never overwrite those changes.
    if read(PAM / 'sddm') != old_login or read(PAM / 'pond-fingerprint') != old_lock or read(PAM / 'pond-password') != old_password:
        raise RuntimeError('PAM changed during installation. Run setup again to recheck it.')
    atomic_write(PAM / 'pond-password', PASSWORD)
    atomic_write(PAM / 'pond-fingerprint', LOCK)
    if new_login != old_login:
        atomic_write(PAM / 'sddm', new_login)
    print('Setup complete. Enroll a finger below. The reader activates on demand.', flush=True)


if __name__ == '__main__':
    try:
        if sys.argv[1:] == ['status']:
            print(json.dumps(status()))
        elif sys.argv[1:] == ['launch']:
            command = launch_command()
            os.execv(command[0], command)
        elif sys.argv[1:] == ['setup']:
            setup()
        else:
            raise ValueError('Expected status, launch or setup')
    except Exception as error:
        print(str(error), file=sys.stderr, flush=True)
        sys.exit(1)
