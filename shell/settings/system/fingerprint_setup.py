#!/usr/bin/python3 -I
"""Fixed-purpose privileged setup. No caller-controlled commands or paths."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

HELPER = '/usr/libexec/pond-fingerprint-setup'
PAM = Path('/etc/pam.d')
LOCK = 'auth required pam_fprintd.so max-tries=3 timeout=30\naccount required pam_unix.so\n'
LOGIN = 'auth sufficient pam_fprintd.so max-tries=3 timeout=30\n'


def packages():
    distro = __import__('platform').freedesktop_os_release().get('ID', '')
    return {
        'ubuntu': ['/usr/bin/apt-get', 'install', '-y', 'fprintd', 'libpam-fprintd'],
        'debian': ['/usr/bin/apt-get', 'install', '-y', 'fprintd', 'libpam-fprintd'],
        'arch': ['/usr/bin/pacman', '-S', '--needed', '--noconfirm', 'fprintd'],
        'fedora': ['/usr/bin/dnf', 'install', '-y', 'fprintd', 'fprintd-pam'],
    }.get(distro)


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
    if not list(Path('/usr/lib').glob('**/security/pam_fprintd.so')) and not list(Path('/lib').glob('*/security/pam_fprintd.so')):
        missing.append('PAM fingerprint module')
    if read(PAM / 'pond-fingerprint') != LOCK:
        missing.append('lock screen configuration')
    sddm = read(PAM / 'sddm')
    if sddm and LOGIN not in sddm.splitlines(keepends=True):
        missing.append('SDDM configuration')
    return {'ready': not missing, 'missing': missing,
            'canSetup': bool(packages() and shutil.which('pkexec') and Path(HELPER).is_file()),
            'sddm': bool(sddm)}


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
    old_lock = read(PAM / 'pond-fingerprint')
    old_login = read(PAM / 'sddm')
    new_login = old_login if not old_login or LOGIN in old_login.splitlines(keepends=True) else login_config(old_login)
    # Validate all files before package installation or PAM changes.
    for name, old in (('pond-fingerprint', old_lock), ('sddm', old_login)):
        backup = PAM / (name + '.pond-backup')
        if old and not backup.exists():
            read(backup)
            with backup.open('x') as stream:
                stream.write(old)
    print('Installing fingerprint support…', flush=True)
    subprocess.run(command, check=True, env={'PATH': '/usr/sbin:/usr/bin:/sbin:/bin', 'DEBIAN_FRONTEND': 'noninteractive', 'LC_ALL': 'C'})
    # A package manager may have modified PAM; never overwrite those changes.
    if read(PAM / 'sddm') != old_login or read(PAM / 'pond-fingerprint') != old_lock:
        raise RuntimeError('PAM changed during installation. Run setup again to recheck it.')
    atomic_write(PAM / 'pond-fingerprint', LOCK)
    if new_login != old_login:
        atomic_write(PAM / 'sddm', new_login)
    print('Setup complete. Enroll a finger below. The reader activates on demand.', flush=True)


if __name__ == '__main__':
    try:
        if sys.argv[1:] == ['status']:
            print(json.dumps(status()))
        elif sys.argv[1:] == ['setup']:
            setup()
        else:
            raise ValueError('Expected status or setup')
    except Exception as error:
        print(str(error), file=sys.stderr, flush=True)
        sys.exit(1)
