import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch
from types import SimpleNamespace

spec = importlib.util.spec_from_file_location('fingerprints', Path(__file__).resolve().parents[1] / 'shell/settings/system/fingerprints.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class FingerprintCommands(unittest.TestCase):
    @patch.object(module.pwd, 'getpwuid', return_value=SimpleNamespace(pw_name='real-user'))
    def test_identity_and_enrollment(self, lookup):
        with patch.dict(module.os.environ, USER='someone-else'):
            self.assertEqual(module.command(['delete']), ['fprintd-delete', 'real-user'])
            for finger in module.FINGERS:
                self.assertEqual(module.command(['enroll', finger]), ['fprintd-enroll', '-f', finger, 'real-user'])
        lookup.assert_called_with(module.os.getuid())

    def test_rejects_arbitrary_arguments(self):
        for args in ([], ['delete', 'root'], ['enroll', '--help'], ['verify', 'root']):
            with self.assertRaises(ValueError):
                module.command(args)


if __name__ == '__main__':
    unittest.main()
