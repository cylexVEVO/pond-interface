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

class EnrollmentFeedback(unittest.TestCase):
    def test_scan_statuses(self):
        for status in module.MESSAGES:
            event = module.feedback('Enroll result: ' + status)
            self.assertEqual(event['status'], status)
            self.assertTrue(event['message'])
        self.assertEqual(module.feedback('Enroll result: enroll-stage-passed')['kind'], 'accepted')
        self.assertEqual(module.feedback('Enroll result: enroll-finger-not-centered')['kind'], 'retry')
        self.assertEqual(module.feedback('Enroll result: enroll-completed')['kind'], 'complete')
        for status in ('enroll-failed', 'enroll-duplicate', 'enroll-disconnected', 'enroll-data-full'):
            self.assertEqual(module.feedback('Enroll result: ' + status)['kind'], 'failed')

    def test_log_is_not_success(self):
        self.assertEqual(module.feedback('Using device /net/reactivated/Fprint/Device/0')['kind'], 'log')
        self.assertEqual(module.feedback('Enroll result: enroll-new-error')['kind'], 'failed')

    def test_streams_before_child_exits(self):
        import json
        import select
        import subprocess
        import sys
        script = "import importlib.util; s=importlib.util.spec_from_file_location('fp', %r); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); m.enroll([%r, '-c', %r])" % (
            str(Path(module.__file__).resolve()), sys.executable,
            "import time; print('Enroll result: enroll-stage-passed'); time.sleep(10)")
        process = subprocess.Popen([sys.executable, '-c', script], stdout=subprocess.PIPE)
        try:
            ready, _, _ = select.select([process.stdout], [], [], 3)
            self.assertTrue(ready, 'Scan feedback was buffered until process exit')
            self.assertEqual(json.loads(process.stdout.readline())['kind'], 'accepted')
            self.assertIsNone(process.poll())
        finally:
            process.terminate()
            process.wait(timeout=5)
            process.stdout.close()

class SavedFingerList(unittest.TestCase):
    def test_parses_only_numbered_fingers_and_deduplicates(self):
        output = '''found 2 devices
Fingerprints for user right-thumb on Reader:
 - #0: right-index-finger
 - #1: left-thumb
 - #0: right-index-finger
'''
        self.assertEqual(module.saved_fingers(output), ['right-index-finger', 'left-thumb'])

    def test_empty_inventory(self):
        self.assertEqual(module.saved_fingers('User has no fingers enrolled'), [])

    def test_verification_feedback(self):
        self.assertEqual(module.feedback('Verify result: verify-match')['kind'], 'complete')
        self.assertEqual(module.feedback('Verify result: verify-no-match')['kind'], 'failed')
