"""Night display validation, scheduling, persistence and gamma-control ownership."""
from array import array
from datetime import datetime, timezone
import importlib.util
import json
import os
from pathlib import Path
import select
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time
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
        self.assertIsNone(night.temperature(self.settings()))
        self.assertIsNone(night.temperature(self.settings(enabled=True, intensity=0)))

    def test_intensity_and_manual_mode(self):
        for intensity, expected in [(0.5, 4250), (1, 2000)]:
            self.assertEqual(night.temperature(self.settings(enabled=True, intensity=intensity)), expected)
        self.assertEqual(night.whitepoint(night.NEUTRAL), (1, 1, 1))
        red, green, blue = night.whitepoint(2000)
        self.assertEqual(red, 1)
        self.assertLess(blue, green)
        data = array('H', night.ramp(2000, 4))
        self.assertEqual(len(data), 12)
        self.assertEqual(list(data[:4]), [0, 21845, 43690, 65535])
        self.assertLess(data[11], data[7])

    def test_custom_boundaries_in_both_directions(self):
        for start, end, active_hours in [('20:00', '07:00', list(range(7)) + list(range(20, 24))),
                                          ('09:00', '17:00', list(range(9, 17)))]:
            settings = self.settings(enabled=True, schedule='custom', start=start, end=end)
            for hour in range(24):
                with self.subTest(start=start, hour=hour):
                    kelvin = night.temperature(settings, datetime(2026, 11, 8, hour))
                    self.assertEqual(kelvin is not None, hour in active_hours)

    def test_solar_location_and_polar_coordinates(self):
        with self.assertRaisesRegex(ValueError, 'latitude'):
            night.temperature(self.settings(enabled=True, schedule='solar'))
        montreal = self.settings(enabled=True, schedule='solar', latitude='45.5', longitude='-73.6')
        utc = lambda hour, minute=0: datetime(2026, 11, 18, hour, minute, tzinfo=timezone.utc)
        self.assertIsNone(night.temperature(montreal, utc(17)))            # midday
        self.assertEqual(night.temperature(montreal, utc(3)), 4250)         # midnight
        dusk = [night.temperature(montreal, utc(21, minute)) or 6500 for minute in range(0, 60, 5)]
        self.assertEqual(dusk, sorted(dusk, reverse=True))                  # gradual sunset
        self.assertTrue(any(4250 < kelvin < 6500 for kelvin in dusk))
        # December: polar night in the north, polar day in the south.
        december = datetime(2026, 12, 21, 12, tzinfo=timezone.utc)
        self.assertEqual(night.temperature(self.settings(enabled=True, schedule='solar', latitude='90', longitude='-180'), december), 4250)
        self.assertIsNone(night.temperature(self.settings(enabled=True, schedule='solar', latitude='-90', longitude='-180'), december))

    def test_invalid_settings(self):
        for patch in [dict(start='24:00'), dict(end='7:00'), dict(start='07:00'),
                      dict(latitude='nan'), dict(longitude='181'), dict(latitude='abc'),
                      dict(intensity=float('inf')), dict(intensity=-1), dict(enabled='yes'),
                      dict(schedule='unknown'), dict(unknown=True)]:
            with self.subTest(patch=patch), self.assertRaises((ValueError, TypeError)):
                self.settings(**patch)

    def service(self, temp, **settings):
        gamma = Mock(failed=False)
        connect = Mock(return_value=gamma)
        service = night.Service(Path(temp) / 'night.json', connect)
        service.settings = self.settings(**settings)
        return service, connect, gamma

    def test_equivalent_warm_schedules_never_touch_gamma(self):
        with tempfile.TemporaryDirectory() as temp, contextlib.redirect_stdout(io.StringIO()), \
                patch.object(night, 'datetime') as clock:
            clock.now.return_value.astimezone.return_value = datetime(2026, 11, 18, 22, tzinfo=timezone.utc)
            service, connect, gamma = self.service(temp, enabled=True, latitude='45.5', longitude='-73.6')
            service.apply()
            gamma.set.assert_called_once_with(4250)
            for change in [dict(schedule='manual'), dict(schedule='custom'), dict(schedule='custom'),
                           dict(start='21:00'), dict(schedule='solar'), dict(schedule='solar'),
                           dict(latitude='45.6'), dict(schedule='manual')]:
                service.update(change)
                self.assertEqual(json.loads(service.path.read_text()), service.settings)
            gamma.set.assert_called_once()
            gamma.close.assert_not_called()
            connect.assert_called_once()

    def test_changes_update_ramps_in_place(self):
        with tempfile.TemporaryDirectory() as temp, contextlib.redirect_stdout(io.StringIO()):
            service, connect, gamma = self.service(temp)
            service.apply()
            connect.assert_not_called()
            service.update(dict(enabled=True))
            service.update(dict(intensity=1))
            service.update(dict(enabled=False))
            service.update(dict(enabled=True))
            self.assertEqual([c.args[0] for c in gamma.set.call_args_list], [4250, 2000, None, 2000])
            gamma.close.assert_not_called()
            connect.assert_called_once()

    def test_connection_failure_retries_on_edit(self):
        with tempfile.TemporaryDirectory() as temp, contextlib.redirect_stdout(io.StringIO()):
            service, connect, gamma = self.service(temp)
            connect.side_effect = [night.GammaError('Could not connect.'), gamma]
            service.update(dict(enabled=True))
            self.assertEqual(service.error, 'Could not connect.')
            self.assertTrue(service.settings['enabled'])
            service.update(dict(enabled=True))
            self.assertEqual(service.error, '')
            gamma.set.assert_called_once_with(4250)

    def test_gamma_protocol_with_hotplug_and_release(self):
        with tempfile.TemporaryDirectory() as temp:
            compositor = FakeCompositor(Path(temp) / 'wayland-test')
            gamma = night.Gamma(str(compositor.path))
            gamma.set(3000)
            compositor.wait(lambda: len(compositor.ramps) == 1, gamma)
            output, data = compositor.ramps[0]
            self.assertEqual(len(data), 3 * 4)
            self.assertEqual(data[3], 65535)
            gamma.set(2500)  # same control, new ramp: no release in between
            compositor.wait(lambda: len(compositor.ramps) == 2, gamma)
            self.assertEqual(compositor.destroyed, 0)
            self.assertLess(compositor.ramps[1][1][11], data[11])
            compositor.add_output()
            compositor.wait(lambda: len(compositor.ramps) == 3, gamma)
            self.assertNotEqual(compositor.ramps[2][0], output)
            gamma.set(None)
            compositor.wait(lambda: compositor.destroyed == 2, gamma)
            gamma.close()
            compositor.close()

    def test_service_lifecycle_and_saved_settings(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            compositor = FakeCompositor(base / 'wayland-test')
            env = dict(os.environ, XDG_CONFIG_HOME=temp, WAYLAND_DISPLAY=str(compositor.path))
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
                compositor.wait(lambda: len(compositor.ramps) == 1)
                self.assertEqual(update(dict(schedule='manual'))['error'], '')
                result = update(dict(start='25:00'))
                self.assertTrue(result['error'])
                self.assertEqual(result['settings']['start'], '20:00')
                process.stdin.close()
                process.wait(timeout=5)
                self.assertEqual(process.returncode, 0, process.stderr.read())
                compositor.wait(lambda: compositor.disconnected)
                self.assertEqual(len(compositor.ramps), 1)  # reselection and invalid edits keep the ramp
                saved = night.Service(base / 'pond-interface/night-display.json')
                self.assertTrue(saved.settings['enabled'])
                self.assertEqual(saved.settings['schedule'], 'manual')
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=5)
                process.stdout.close()
                process.stderr.close()
                compositor.close()


class FakeCompositor:
    """Just enough of a Wayland server for wl_registry and wlr-gamma-control."""
    SIZE = 4

    def __init__(self, path):
        self.path = path
        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server.bind(str(path))
        self.server.listen(1)
        self.client = None
        self.globals = [(1, 'wl_output'), (2, 'zwlr_gamma_control_manager_v1')]
        self.ramps, self.destroyed, self.disconnected = [], 0, False
        self.registry, self.controls, self.bound = None, {}, {}
        self.lock = threading.Lock()
        self.thread = threading.Thread(target=self.serve, daemon=True)
        self.thread.start()

    def event(self, object_id, opcode, payload=b''):
        self.client.sendall(struct.pack('=II', object_id, (8 + len(payload)) << 16 | opcode) + payload)

    def announce(self, name, interface):
        data = interface.encode() + b'\0'
        self.event(self.registry, 0, struct.pack('=II', name, len(data)) + data + b'\0' * (-len(data) % 4) + struct.pack('=I', 1))

    def add_output(self):
        with self.lock:
            self.globals.append((3, 'wl_output'))
            self.announce(3, 'wl_output')

    def serve(self):
        self.client, _ = self.server.accept()
        buffer, fds = b'', []
        while True:
            data, ancillary, _, _ = self.client.recvmsg(65536, socket.CMSG_SPACE(16 * 4))
            for level, kind, payload in ancillary:
                if level == socket.SOL_SOCKET and kind == socket.SCM_RIGHTS:
                    fds.extend(array('i', payload[:len(payload) - len(payload) % 4]))
            if not data:
                self.disconnected = True
                return
            buffer += data
            while len(buffer) >= 8:
                object_id, header = struct.unpack_from('=II', buffer)
                size, opcode = header >> 16, header & 0xffff
                if len(buffer) < size:
                    break
                payload, buffer = buffer[8:size], buffer[size:]
                with self.lock:
                    self.handle(object_id, opcode, payload, fds)

    def handle(self, object_id, opcode, payload, fds):
        if object_id == 1 and opcode == 1:  # get_registry
            self.registry, = struct.unpack('=I', payload)
            for name, interface in self.globals:
                self.announce(name, interface)
        elif object_id == 1 and opcode == 0:  # sync
            callback, = struct.unpack('=I', payload)
            self.event(callback, 0, struct.pack('=I', 0))
        elif object_id == self.registry:  # bind
            name, length = struct.unpack_from('=II', payload)
            new_id, = struct.unpack_from('=I', payload, 8 + length + (-length % 4) + 4)
            self.bound[new_id] = name
        elif self.bound.get(object_id) == 2 and opcode == 0:  # get_gamma_control
            control, output = struct.unpack('=II', payload)
            self.controls[control] = self.bound[output]
            self.event(control, 0, struct.pack('=I', self.SIZE))
        elif object_id in self.controls and opcode == 0:  # set_gamma
            fd = fds.pop(0)
            self.ramps.append((self.controls[object_id], array('H', os.pread(fd, 6 * self.SIZE, 0))))
            os.close(fd)
        elif object_id in self.controls and opcode == 1:
            del self.controls[object_id]
            self.destroyed += 1

    def wait(self, condition, gamma=None):
        deadline = time.monotonic() + 5
        while not condition():
            if time.monotonic() > deadline:
                raise AssertionError('fake compositor timed out')
            if gamma and select.select([gamma], [], [], 0.01)[0]:
                gamma.dispatch()
            else:
                time.sleep(0.01)

    def close(self):
        if self.client:
            self.client.close()
        self.server.close()


if __name__ == '__main__':
    unittest.main()
