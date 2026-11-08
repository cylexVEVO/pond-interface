"""Night display validation, command generation, persistence and process ownership."""
from datetime import datetime
import importlib.util
import json
import os
from pathlib import Path
import select
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch
import contextlib
import io

SCRIPT = Path(__file__).resolve().parents[1] / 'shell/settings/night/control.py'
spec = importlib.util.spec_from_file_location('night_display', SCRIPT)
night = importlib.util.module_from_spec(spec)
spec.loader.exec_module(night)


class NightDisplay(unittest.TestCase):
    def settings(self, **patch):
        return night.validate(patch, night.DEFAULTS)

    def test_off_and_zero_release_gamma(self):
        self.assertIsNone(night.command(self.settings()))
        self.assertIsNone(night.command(self.settings(enabled=True, intensity=0)))

    def test_intensity_and_manual_mode(self):
        for intensity, expected in [(0.5, '4250'), (1, '2000')]:
            args = night.command(self.settings(enabled=True, intensity=intensity))
            self.assertEqual(args[args.index('-t') + 1], expected)
            self.assertEqual(int(args[args.index('-T') + 1]), int(expected) + 1)

    def test_custom_boundaries_in_both_directions(self):
        for start, end, active_hours in [('20:00', '07:00', list(range(7)) + list(range(20, 24))),
                                          ('09:00', '17:00', list(range(9, 17)))]:
            settings = self.settings(enabled=True, schedule='custom', start=start, end=end)
            for hour in range(24):
                with self.subTest(start=start, hour=hour):
                    args = night.command(settings, datetime(2026, 11, 8, hour))
                    self.assertEqual(args is not None, hour in active_hours)

    def test_solar_location_and_polar_coordinates(self):
        with self.assertRaisesRegex(ValueError, 'latitude'):
            night.command(self.settings(enabled=True, schedule='solar'))
        for lat in ['0', '-90', '90']:
            args = night.command(self.settings(enabled=True, schedule='solar', latitude=lat, longitude='-180'))
            self.assertEqual(float(args[args.index('-l') + 1]), float(lat))
            self.assertNotIn('-s', args)

    def test_invalid_settings(self):
        for patch in [dict(start='24:00'), dict(end='7:00'), dict(start='07:00'),
                      dict(latitude='nan'), dict(longitude='181'), dict(latitude='abc'),
                      dict(intensity=float('inf')), dict(intensity=-1), dict(enabled='yes'),
                      dict(schedule='unknown'), dict(unknown=True)]:
            with self.subTest(patch=patch), self.assertRaises((ValueError, TypeError)):
                self.settings(**patch)

    def test_equivalent_active_schedules_keep_gamma_owner(self):
        with tempfile.TemporaryDirectory() as temp:
            service = night.Service(Path(temp) / 'night.json')
            service.settings = self.settings(enabled=True)
            service.applied_args = night.command(service.settings)
            child = service.child = Mock()
            child.poll.return_value = None
            with patch.object(night, 'datetime') as clock, patch.object(night.subprocess, 'Popen') as launch, contextlib.redirect_stdout(io.StringIO()):
                clock.now.return_value.astimezone.return_value = datetime(2026, 11, 8, 22)
                for change in [dict(schedule='manual'), dict(schedule='custom'),
                               dict(schedule='custom'), dict(start='21:00'),
                               dict(schedule='manual')]:
                    service.update(change)
                    self.assertIs(service.child, child)
                    child.terminate.assert_not_called()
                    launch.assert_not_called()
                    self.assertEqual(json.loads(service.path.read_text()), service.settings)

    def test_solar_reselection_keeps_gamma_owner(self):
        with tempfile.TemporaryDirectory() as temp:
            service = night.Service(Path(temp) / 'night.json')
            service.settings = self.settings(enabled=True, schedule='solar', latitude='45', longitude='-73')
            service.applied_args = night.command(service.settings)
            child = service.child = Mock()
            child.poll.return_value = None
            with patch.object(night.subprocess, 'Popen') as launch, contextlib.redirect_stdout(io.StringIO()):
                service.update(dict(schedule='solar'))
                child.terminate.assert_not_called()
                launch.assert_not_called()

    def test_changed_output_and_dead_backend_are_applied(self):
        with tempfile.TemporaryDirectory() as temp:
            service = night.Service(Path(temp) / 'night.json')
            service.settings = self.settings(enabled=True)
            service.applied_args = night.command(service.settings)
            child = service.child = Mock()
            child.poll.return_value = None
            with patch.object(night.subprocess, 'Popen') as launch, patch.object(night.shutil, 'which', return_value='/usr/bin/wlsunset'), patch.object(night.os, 'set_blocking'), contextlib.redirect_stdout(io.StringIO()):
                service.update(dict(intensity=0.8))
                child.terminate.assert_called_once()
                self.assertEqual(launch.call_count, 1)
                service.child.poll.return_value = 1
                service.update(dict(intensity=0.8))
                self.assertEqual(launch.call_count, 2)
                service.update(dict(enabled=False))
                self.assertIsNone(service.child)
                self.assertEqual(launch.call_count, 2)

    def test_missing_backend_preserves_settings_and_reports_error(self):
        with tempfile.TemporaryDirectory() as temp:
            service = night.Service(Path(temp) / 'night.json')
            with patch.object(night.shutil, 'which', return_value=None), contextlib.redirect_stdout(io.StringIO()):
                service.update(dict(enabled=True))
                self.assertIn('requires wlsunset', service.error)
                self.assertTrue(service.settings['enabled'])
                self.assertIsNone(service.child)
                service.update(dict(enabled=False))
                self.assertEqual(service.error, '')

    def test_service_lifecycle_and_saved_settings(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            fake = base / 'wlsunset'
            fake.write_text('#!' + sys.executable + '\nimport os, time\nfrom pathlib import Path\nPath(os.environ["PID_FILE"]).write_text(str(os.getpid()))\nwhile True: time.sleep(1)\n')
            fake.chmod(0o755)
            env = dict(os.environ, XDG_CONFIG_HOME=temp, PATH=temp + os.pathsep + os.environ['PATH'], PID_FILE=str(base / 'pid'))
            process = subprocess.Popen([sys.executable, str(SCRIPT)], env=env, stdin=subprocess.PIPE,
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            def read():
                self.assertTrue(select.select([process.stdout], [], [], 5)[0], 'service response timed out')
                return json.loads(process.stdout.readline())
            def update(patch):
                process.stdin.write(json.dumps(patch).encode() + b'\n')
                process.stdin.flush()
                return read()
            try:
                self.assertFalse(read()['settings']['enabled'])
                self.assertEqual(update(dict(enabled=True, schedule='manual'))['error'], '')
                # Wait for fake backend startup without depending on arbitrary sleep durations.
                import time
                deadline = time.monotonic() + 3
                while not (base / 'pid').exists() and time.monotonic() < deadline:
                    time.sleep(0.01)
                pid = int((base / 'pid').read_text())
                result = update(dict(start='25:00'))
                self.assertTrue(result['error'])
                self.assertEqual(result['settings']['start'], '20:00')
                os.kill(pid, 0)  # Invalid edits preserve the running backend.
                process.stdin.close()
                process.wait(timeout=5)
                self.assertEqual(process.returncode, 0, process.stderr.read())
                with self.assertRaises(ProcessLookupError):
                    os.kill(pid, 0)
                saved = night.Service(base / 'pond-interface/night-display.json')
                self.assertTrue(saved.settings['enabled'])
                self.assertEqual(saved.settings['schedule'], 'manual')
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=5)
                process.stdout.close()
                process.stderr.close()


if __name__ == '__main__':
    unittest.main()
