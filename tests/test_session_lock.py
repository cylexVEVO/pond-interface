import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch, Mock

spec = importlib.util.spec_from_file_location(
    'session', Path(__file__).resolve().parents[1] / 'shell/settings/session.py')
session = importlib.util.module_from_spec(spec)
spec.loader.exec_module(session)


class SessionLockTests(unittest.TestCase):
    def test_current_requires_bundled_pam(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            self.assertFalse(session.is_current(path))
            pam = path / 'session' / 'pam.d'
            pam.mkdir(parents=True)
            (pam / 'pond-password').write_text('auth required pam_unix.so\n')
            (pam / 'pond-fingerprint').write_text('auth required pam_fprintd.so\n')
            self.assertTrue(session.is_current(path))

    def test_lock_restarts_when_bundle_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            adjacent = root / 'lockscreen'
            pam = adjacent / 'session' / 'pam.d'
            pam.mkdir(parents=True)
            (pam / 'pond-password').write_text('auth required pam_unix.so\n')
            (pam / 'pond-fingerprint').write_text('auth required pam_fprintd.so\n')
            (adjacent / 'session' / 'Authentication.qml').write_text('AuthSession {}\n')
            started = []

            def fake_run(command, **kwargs):
                if command[:2] == ['qs', '-d']:
                    started.append(command[3])
                    return Mock(returncode=0)
                if command[:2] == ['qs', '-p']:
                    return Mock(returncode=1)
                if command[0] == 'pgrep':
                    return Mock(returncode=1, stdout='')
                return Mock(returncode=0)

            with patch.object(session, 'lockscreen_candidates', return_value=[adjacent]), \
                    patch.object(session.subprocess, 'run', side_effect=fake_run), \
                    patch.object(session.time, 'sleep'), \
                    patch.dict(session.os.environ, {'XDG_RUNTIME_DIR': str(root / 'run')}, clear=False):
                session.run('lock')
            self.assertEqual(started, [str(adjacent)])
            marker = root / 'run' / 'pond-lockscreen-bundle'
            self.assertTrue(marker.is_file())
