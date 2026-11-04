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
            with patch.object(setup, 'PAM', Path(directory)), patch.object(setup, 'packages', return_value=['installer']), patch.object(setup.shutil, 'which', return_value='/usr/bin/tool'):
                result = setup.status()
            self.assertTrue(result['canSetup'])
            self.assertFalse(result['ready'])
            self.assertEqual(result['blocker'], '')
