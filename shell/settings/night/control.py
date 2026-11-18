#!/usr/bin/env python3
"""Shell-owned night display service. stdin EOF releases the display gamma ramps.

The service is its own wlr-gamma-control client. Holding the gamma controls for as
long as the display should be warm means a settings change only uploads new ramps;
releasing a control (as restarting an external tool does) restores neutral colors
for a frame, which shows as a flicker.
"""
from array import array
from datetime import datetime, timezone
import json
import math
import os
from pathlib import Path
import re
import select
import signal
import socket
import struct
import sys

DEFAULTS = dict(enabled=False, intensity=0.5, schedule='manual', start='20:00',
                end='07:00', latitude='', longitude='')
NEUTRAL = 6500
WARMEST = 2000
# Solar mode is neutral above DAY_ELEVATION and fully warm below NIGHT_ELEVATION
# (civil dusk), so sunset and sunrise fade gradually, including polar day and night.
DAY_ELEVATION = 3.0
NIGHT_ELEVATION = -6.0
J2000 = datetime(2000, 1, 1, 12, tzinfo=timezone.utc)


def validate(patch, current):
    result = dict(current)
    if not isinstance(patch, dict) or patch.keys() - DEFAULTS.keys():
        raise ValueError('Invalid night display settings.')
    result.update(patch)
    if type(result['enabled']) is not bool:
        raise ValueError('Invalid enabled setting.')
    intensity = float(result['intensity'])
    if not math.isfinite(intensity) or not 0 <= intensity <= 1:
        raise ValueError('Intensity must be between 0 and 100%.')
    result['intensity'] = intensity
    if result['schedule'] not in ('manual', 'custom', 'solar'):
        raise ValueError('Invalid schedule.')
    for key in ('start', 'end'):
        if not isinstance(result[key], str) or not re.fullmatch(r'(?:[01]\d|2[0-3]):[0-5]\d', result[key]):
            raise ValueError('Enter times in 24-hour HH:MM format.')
    if result['start'] == result['end']:
        raise ValueError('Start and end times must be different.')
    for key, limit in [('latitude', 90), ('longitude', 180)]:
        value = result[key]
        if value != '':
            number = float(value)
            if not math.isfinite(number) or not -limit <= number <= limit:
                raise ValueError(f'{key.capitalize()} must be between {-limit} and {limit}.')
            result[key] = str(number)
    return result


def solar_elevation(latitude, longitude, when):
    """Approximate solar elevation in degrees (accurate to a fraction of a degree)."""
    days = (when - J2000).total_seconds() / 86400
    anomaly = math.radians((357.529 + 0.98560028 * days) % 360)
    mean = (280.459 + 0.98564736 * days) % 360
    ecliptic = math.radians(mean + 1.915 * math.sin(anomaly) + 0.020 * math.sin(2 * anomaly))
    obliquity = math.radians(23.439 - 0.00000036 * days)
    ascension = math.atan2(math.cos(obliquity) * math.sin(ecliptic), math.cos(ecliptic))
    declination = math.asin(math.sin(obliquity) * math.sin(ecliptic))
    sidereal = (18.697374558 + 24.06570982441908 * days) % 24
    hour_angle = math.radians(sidereal * 15 + longitude) - ascension
    latitude = math.radians(latitude)
    return math.degrees(math.asin(max(-1, min(1, math.sin(latitude) * math.sin(declination) +
        math.cos(latitude) * math.cos(declination) * math.cos(hour_angle)))))


def temperature(settings, now=None):
    """Target color temperature in kelvin, or None to release gamma control."""
    if not settings['enabled'] or settings['intensity'] == 0:
        return None
    now = now or datetime.now().astimezone()
    warm = NEUTRAL - (NEUTRAL - WARMEST) * settings['intensity']
    if settings['schedule'] == 'custom':
        minute = now.hour * 60 + now.minute
        start, end = [int(settings[key][:2]) * 60 + int(settings[key][3:])
                      for key in ('start', 'end')]
        active = start <= minute < end if start < end else minute >= start or minute < end
        if not active:
            return None
    elif settings['schedule'] == 'solar':
        if settings['latitude'] == '' or settings['longitude'] == '':
            raise ValueError('Enter your latitude and longitude for sunset to sunrise.')
        elevation = solar_elevation(float(settings['latitude']), float(settings['longitude']), now)
        night = (DAY_ELEVATION - elevation) / (DAY_ELEVATION - NIGHT_ELEVATION)
        warm = NEUTRAL - (NEUTRAL - warm) * max(0.0, min(1.0, night))
    kelvin = round(warm)
    return None if kelvin >= NEUTRAL else kelvin


def whitepoint(kelvin):
    """Blackbody RGB multipliers, normalized so NEUTRAL is (1, 1, 1)."""
    def raw(k):
        t = k / 100
        red = 1.0 if t <= 66 else 329.698727446 * (t - 60) ** -0.1332047592 / 255
        green = ((99.4708025861 * math.log(t) - 161.1195681661) if t <= 66
                 else 288.1221695283 * (t - 60) ** -0.0755148492) / 255
        blue = 1.0 if t >= 66 else 0.0 if t <= 19 else (138.5177312231 * math.log(t - 10) - 305.0447927307) / 255
        return red, green, blue
    return tuple(max(0.0, min(1.0, value / base)) for value, base in zip(raw(kelvin), raw(NEUTRAL)))


def ramp(kelvin, size):
    data = array('H')
    for channel in whitepoint(kelvin):
        data.extend(round(channel * 65535 * i / max(1, size - 1)) for i in range(size))
    return data.tobytes()


class GammaError(Exception):
    pass


class Gamma:
    """Minimal Wayland client for zwlr_gamma_control_manager_v1 on every output."""
    MANAGER = 'zwlr_gamma_control_manager_v1'

    def __init__(self, path=None):
        if path is None:
            display = os.environ.get('WAYLAND_DISPLAY', 'wayland-0')
            path = display if display.startswith('/') else os.path.join(os.environ.get('XDG_RUNTIME_DIR', ''), display)
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM | socket.SOCK_CLOEXEC)
        try:
            self.sock.connect(path)
        except OSError as exc:
            self.sock.close()
            raise GammaError('Could not connect to the display server for night display.') from exc
        self.buffer = b''
        self.next_id = 2
        self.handlers = {}
        self.outputs = {}    # registry name -> wl_output id
        self.controls = {}   # registry name -> [control id, gamma size or None]
        self.manager = None
        self.kelvin = None
        self.failed = False
        self.registry = self.new_id(self.on_registry)
        self.send(1, 1, struct.pack('=I', self.registry))  # wl_display.get_registry
        self.roundtrip()
        if self.manager is None:
            self.close()
            raise GammaError('This display server does not support night display (wlr-gamma-control).')

    def new_id(self, handler=None):
        object_id = self.next_id
        self.next_id += 1
        self.handlers[object_id] = handler
        return object_id

    def send(self, object_id, opcode, payload=b'', fd=None):
        message = struct.pack('=II', object_id, (8 + len(payload)) << 16 | opcode) + payload
        try:
            if fd is None:
                self.sock.sendall(message)
            else:
                self.sock.sendmsg([message], [(socket.SOL_SOCKET, socket.SCM_RIGHTS, array('i', [fd]))])
        except OSError as exc:
            raise GammaError('Lost connection to the display server.') from exc

    @staticmethod
    def string(value):
        data = value.encode() + b'\0'
        return struct.pack('=I', len(data)) + data + b'\0' * (-len(data) % 4)

    def roundtrip(self):
        done = []
        callback = self.new_id(lambda opcode, payload: done.append(True))
        self.send(1, 0, struct.pack('=I', callback))  # wl_display.sync
        while not done:
            select.select([self.sock], [], [])
            self.dispatch()

    def fileno(self):
        return self.sock.fileno()

    def dispatch(self):
        try:
            chunk = self.sock.recv(65536)
        except BlockingIOError:
            return
        except OSError as exc:
            raise GammaError('Lost connection to the display server.') from exc
        if not chunk:
            raise GammaError('Lost connection to the display server.')
        self.buffer += chunk
        while len(self.buffer) >= 8:
            object_id, header = struct.unpack_from('=II', self.buffer)
            size = header >> 16
            if size < 8 or len(self.buffer) < size:
                break
            payload, self.buffer = self.buffer[8:size], self.buffer[size:]
            if object_id == 1:
                if header & 0xffff == 0:  # wl_display.error
                    raise GammaError('The display server rejected night display.')
                continue  # wl_display.delete_id
            handler = self.handlers.get(object_id)
            if handler:
                handler(header & 0xffff, payload)

    def on_registry(self, opcode, payload):
        if opcode == 0:  # global(name, interface, version)
            name, length = struct.unpack_from('=II', payload)
            interface = payload[8:8 + length - 1].decode(errors='replace')
            if interface == 'wl_output':
                self.outputs[name] = self.bind(name, interface, 1)
                self.attach(name)
            elif interface == self.MANAGER and self.manager is None:
                self.manager = self.bind(name, interface, 1)
                for output in self.outputs:
                    self.attach(output)
        elif opcode == 1:  # global_remove(name)
            name, = struct.unpack_from('=I', payload)
            self.outputs.pop(name, None)
            self.detach(name)

    def bind(self, name, interface, version):
        object_id = self.new_id()
        self.send(self.registry, 0, struct.pack('=I', name) + self.string(interface) +
                  struct.pack('=II', version, object_id))
        return object_id

    def attach(self, name):
        if self.kelvin is None or self.manager is None or name in self.controls or name not in self.outputs:
            return
        control = [None, None]
        def on_control(opcode, payload):
            if opcode == 0:  # gamma_size
                control[1], = struct.unpack_from('=I', payload)
                self.upload(control)
            elif opcode == 1:  # failed: another app owns gamma, or the output is gone
                self.failed = name in self.outputs
                self.detach(name)
        control[0] = self.new_id(on_control)
        self.controls[name] = control
        self.send(self.manager, 0, struct.pack('=II', control[0], self.outputs[name]))

    def detach(self, name):
        control = self.controls.pop(name, None)
        if control:
            self.handlers.pop(control[0], None)
            self.send(control[0], 1)  # destroy restores the output's original gamma

    def upload(self, control):
        if not control[1] or self.kelvin is None:
            return
        fd = os.memfd_create('night-display', os.MFD_CLOEXEC)
        try:
            os.write(fd, ramp(self.kelvin, control[1]))
            os.lseek(fd, 0, os.SEEK_SET)
            self.send(control[0], 0, fd=fd)  # set_gamma
        finally:
            os.close(fd)

    def set(self, kelvin):
        """Warm every output in place, or release them all for None."""
        self.kelvin = kelvin
        self.failed = False  # failures arrive asynchronously; detached outputs are retried
        if kelvin is None:
            for name in list(self.controls):
                self.detach(name)
            return
        for name in self.outputs:
            if name in self.controls:
                self.upload(self.controls[name])
            else:
                self.attach(name)

    def close(self):
        try:
            self.set(None)
        except GammaError:
            pass
        self.sock.close()


class Service:
    def __init__(self, path, connect=Gamma):
        self.path = path
        self.connect = connect
        self.settings = dict(DEFAULTS)
        self.gamma = None
        self.error = ''
        self.applied = None
        try:
            self.settings = validate(json.loads(path.read_text()), DEFAULTS)
        except FileNotFoundError:
            pass
        except (ValueError, TypeError, OSError):
            self.error = 'Could not load saved night display settings.'

    def report(self):
        print(json.dumps(dict(settings=self.settings, error=self.error)), flush=True)

    def drop(self):
        if self.gamma:
            self.gamma.close()
            self.gamma = None

    def apply(self):
        try:
            kelvin = temperature(self.settings)
            # Equivalent settings (reselecting a schedule, or switching between two
            # schedules that are both fully warm) leave the ramps untouched.
            if kelvin == self.applied and (kelvin is None or self.gamma is not None):
                self.report()
                return
            self.applied = kelvin
            if kelvin is not None and self.gamma is None:
                self.gamma = self.connect()
            if self.gamma:
                self.gamma.set(kelvin)
        except GammaError as exc:
            self.drop()
            self.error = str(exc)
        except ValueError as exc:
            self.applied = None
            if self.gamma:
                try:
                    self.gamma.set(None)
                except GammaError:
                    self.drop()
            self.error = str(exc)
        self.report()

    def update(self, patch):
        try:
            settings = validate(patch, self.settings)
            self.path.parent.mkdir(parents=True, exist_ok=True)
            temporary = self.path.with_suffix('.tmp')
            temporary.write_text(json.dumps(settings) + '\n')
            temporary.replace(self.path)
            self.settings = settings
            self.error = ''
            self.apply()
        except (ValueError, TypeError, OSError) as exc:
            self.error = str(exc)
            self.report()

    def run(self):
        buffer = b''
        try:
            self.apply()
            while True:
                # Re-evaluate wall-clock time, including resume, DST and timezone changes.
                try:
                    if temperature(self.settings) != self.applied:
                        self.error = ''
                        self.apply()
                except ValueError:
                    pass  # An incomplete solar location is already reported by apply().
                streams = [sys.stdin.buffer] + ([self.gamma] if self.gamma else [])
                ready, _, _ = select.select(streams, [], [], 1)
                if self.gamma and self.gamma in ready:
                    failed = self.gamma.failed
                    try:
                        self.gamma.dispatch()  # gamma sizes, hotplugged outputs, failures
                    except GammaError as exc:
                        self.drop()
                        self.error = f'{exc} Toggle night display off and on to retry.'
                        self.report()
                    else:
                        if self.gamma.failed and not failed:
                            self.error = 'Could not warm one or more displays. Check gamma support and other night light apps.'
                            self.report()
                if sys.stdin.buffer in ready:
                    chunk = os.read(sys.stdin.fileno(), 65536)
                    if not chunk:
                        break
                    buffer += chunk
                    while b'\n' in buffer:
                        line, buffer = buffer.split(b'\n', 1)
                        try:
                            self.update(json.loads(line))
                        except ValueError:
                            self.error = 'Invalid night display request.'
                            self.report()
        finally:
            self.drop()


def main():
    path = Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config'))) / 'pond-interface/night-display.json'
    service = Service(path)
    def shutdown(*_):
        raise SystemExit(0)
    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)
    service.run()


if __name__ == '__main__':
    main()
