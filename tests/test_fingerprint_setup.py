import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('setup', Path(__file__).resolve().parents[1] / 'shell/settings/system/fingerprint_setup.py')
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)


class SetupTests(unittest.TestCase):
    def test_preserves_security_checks_and_password_stack(self):
        original = '# PAM\nauth required pam_nologin.so\nauth include system-login\naccount include system-login\n'
        expected = original.replace('auth include', setup.LOGIN + 'auth include', 1)
        self.assertEqual(setup.login_config(original), expected)

    def test_refuses_custom_fingerprint_stack(self):
        with self.assertRaises(ValueError):
            setup.login_config('auth required pam_fprintd.so\n')

    def test_refuses_unknown_stack(self):
        with self.assertRaises(ValueError):
            setup.login_config('# empty\n')

    def test_setup_is_repeatable_and_keeps_backup(self):
        with tempfile.TemporaryDirectory() as directory:
            pam = Path(directory)
            original = 'auth include system-login\naccount include system-login\n'
            (pam / 'sddm').write_text(original)
            with patch.object(setup, 'PAM', pam), patch.object(setup.os, 'geteuid', return_value=0), patch.object(setup, 'packages', return_value=['installer']), patch.object(setup.subprocess, 'run'):
                setup.setup()
                setup.setup()
            self.assertEqual((pam / 'sddm.pond-backup').read_text(), original)
            self.assertEqual((pam / 'sddm').read_text().count(setup.LOGIN), 1)
            self.assertEqual((pam / 'pond-fingerprint').read_text(), setup.LOCK)
            self.assertEqual((pam / 'pond-password').read_text(), setup.PASSWORD)

    def test_package_failure_does_not_change_pam(self):
        with tempfile.TemporaryDirectory() as directory:
            pam = Path(directory)
            original = 'auth include system-login\n'
            (pam / 'sddm').write_text(original)
            with patch.object(setup, 'PAM', pam), patch.object(setup.os, 'geteuid', return_value=0), patch.object(setup, 'packages', return_value=['installer']), patch.object(setup.subprocess, 'run', side_effect=RuntimeError('failed')):
                with self.assertRaises(RuntimeError):
                    setup.setup()
            self.assertEqual((pam / 'sddm').read_text(), original)
            self.assertFalse((pam / 'pond-fingerprint').exists())

    def test_launch_uses_bundled_script_with_isolated_python(self):
        self.assertEqual(setup.launch_command(), [
            '/usr/bin/pkexec', '/usr/bin/python3', '-I', '-u',
            str(Path(setup.__file__).resolve()), 'setup'])

    def test_setup_available_without_installed_helper(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(setup, 'PAM', Path(directory)), patch.object(setup, 'packages', return_value=['installer']), patch.object(setup.shutil, 'which', return_value='/usr/bin/tool'), patch.object(Path, 'is_file', return_value=True):
                result = setup.status()
            self.assertTrue(result['canSetup'])
            self.assertFalse(result['ready'])
            self.assertEqual(result['blocker'], '')

    def test_arch_derivative_uses_declared_family(self):
        with patch.object(setup, 'distribution', return_value={'ID': 'endeavouros', 'ID_LIKE': 'arch'}):
            self.assertEqual(setup.packages()[0], '/usr/bin/pacman')

    def test_direct_distribution_precedes_family(self):
        with patch.object(setup, 'distribution', return_value={'ID': 'ubuntu', 'ID_LIKE': 'debian'}):
            self.assertEqual(setup.packages()[0], '/usr/bin/apt-get')

    def test_unsupported_system_is_named(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(setup, 'PAM', Path(directory)), patch.object(setup, 'distribution', return_value={'ID': 'unknown-os', 'PRETTY_NAME': 'Example Linux'}), patch.object(Path, 'is_file', return_value=True):
                result = setup.status()
            self.assertFalse(result['canSetup'])
            self.assertIn('Example Linux', result['blocker'])
            self.assertIn('unknown-os', result['blocker'])

    def test_missing_package_manager_and_pkexec_are_explained(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(setup, 'PAM', Path(directory)), patch.object(setup, 'packages', return_value=['/usr/bin/pacman']), patch.object(Path, 'is_file', return_value=False):
                result = setup.status()
            self.assertFalse(result['canSetup'])
            self.assertIn('/usr/bin/pacman', result['blocker'])
            self.assertIn('pkexec is missing', result['blocker'])

    def test_password_service_is_separate_from_fingerprint(self):
        self.assertEqual(setup.PASSWORD, 'auth required pam_unix.so\n')
        self.assertNotIn('pam_fprintd', setup.PASSWORD)
        self.assertNotIn('include', setup.PASSWORD)
        self.assertNotIn('account', setup.PASSWORD)
        self.assertEqual(setup.LOCK, 'auth required pam_fprintd.so max-tries=3 timeout=30\n')
        self.assertNotIn('pam_unix.so', setup.LOCK)
        self.assertNotIn('account', setup.LOCK)
        root = Path(__file__).resolve().parents[1]
        for relative in (
            'config/pam.d/pond-password',
            'config/pam.d/pond-fingerprint',
            'lockscreen/session/pam.d/pond-password',
            'lockscreen/session/pam.d/pond-fingerprint',
        ):
            path = root / relative
            expected = setup.PASSWORD if path.name == 'pond-password' else setup.LOCK
            self.assertEqual(path.read_text(), expected, relative)

    def test_status_requires_current_etc_lock_pam(self):
        with tempfile.TemporaryDirectory() as directory:
            pam = Path(directory)
            (pam / 'pond-fingerprint').write_text('auth required pam_fprintd.so\naccount required pam_unix.so\n')
            with patch.object(setup, 'PAM', pam), patch.object(setup, 'packages', return_value=['installer']), patch.object(setup.shutil, 'which', return_value='/usr/bin/tool'), patch.object(Path, 'is_file', return_value=True), patch.object(Path, 'glob', return_value=[Path('/usr/lib/security/pam_fprintd.so')]):
                result = setup.status()
            self.assertIn('lock screen configuration', result['missing'])
            self.assertIn('password unlock configuration', result['missing'])
            self.assertFalse(result['ready'])
            self.assertIn('lock screen configuration', result['missingLabel'])

    def test_status_ready_when_etc_matches(self):
        with tempfile.TemporaryDirectory() as directory:
            pam = Path(directory)
            (pam / 'pond-fingerprint').write_text(setup.LOCK)
            (pam / 'pond-password').write_text(setup.PASSWORD)
            with patch.object(setup, 'PAM', pam), patch.object(setup, 'packages', return_value=['installer']), patch.object(setup.shutil, 'which', return_value='/usr/bin/tool'), patch.object(Path, 'is_file', return_value=True), patch.object(Path, 'glob', return_value=[Path('/usr/lib/security/pam_fprintd.so')]):
                result = setup.status()
            self.assertEqual(result['missing'], [])
            self.assertTrue(result['ready'])
