#!/usr/bin/env python3
"""Shell-owned night display service. stdin EOF releases the display gamma ramps."""
from datetime import datetime
import json
import math
import os
from pathlib import Path
import re
import select
import shutil
import signal
import subprocess
import sys

DEFAULTS = dict(enabled=False, intensity=0.5, schedule='manual', start='20:00',
                end='07:00', latitude='', longitude='')


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


def command(settings, now=None):
    if not settings['enabled'] or settings['intensity'] == 0:
        return None
    if settings['schedule'] == 'custom':
        now = now or datetime.now().astimezone()
        minute = now.hour * 60 + now.minute
        start, end = [int(settings[key][:2]) * 60 + int(settings[key][3:])
                      for key in ('start', 'end')]
        active = start <= minute < end if start < end else minute >= start or minute < end
        if not active:
            return None
    temperature = min(6499, round(6500 - 4500 * settings['intensity']))
    args = ['wlsunset', '-t', str(temperature)]
    if settings['schedule'] in ('manual', 'custom'):
        # wlsunset requires high > low. Both endpoints are effectively identical.
        return args + ['-T', str(temperature + 1), '-l', '0', '-L', '0']
    args += ['-T', '6500']
    if settings['latitude'] == '' or settings['longitude'] == '':
        raise ValueError('Enter your latitude and longitude for sunset to sunrise.')
    return args + ['-l', settings['latitude'], '-L', settings['longitude']]


class Service:
    def __init__(self, path):
        self.path = path
        self.settings = dict(DEFAULTS)
        self.child = None
        self.error = ''
        self.applied_args = None
        try:
            self.settings = validate(json.loads(path.read_text()), DEFAULTS)
        except FileNotFoundError:
            pass
        except (ValueError, TypeError, OSError):
            self.error = 'Could not load saved night display settings.'

    def report(self):
        print(json.dumps(dict(settings=self.settings, error=self.error)), flush=True)

    def stop(self):
        if self.child:
            self.child.terminate()
            try:
                self.child.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.child.kill()
                self.child.wait()
            self.child.stderr.close()
            self.child = None

    def apply(self):
        self.stop()
        try:
            args = command(self.settings)
            self.applied_args = args
            if args:
                if not shutil.which('wlsunset'):
                    raise ValueError('Night display requires wlsunset. Install it to enable display warming.')
                self.child = subprocess.Popen(args, stdin=subprocess.DEVNULL,
                                              stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
                os.set_blocking(self.child.stderr.fileno(), False)
        except (ValueError, OSError) as exc:
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
                    if command(self.settings) != self.applied_args:
                        self.error = ''
                        self.apply()
                except ValueError:
                    pass  # An incomplete solar location is already reported by apply().
                streams = [sys.stdin.buffer]
                if self.child:
                    streams.append(self.child.stderr)
                ready, _, _ = select.select(streams, [], [], 1)
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
                if self.child and self.child.stderr in ready:
                    message = os.read(self.child.stderr.fileno(), 65536).decode(errors='replace')
                    if any(word in message.lower() for word in ('failed', 'error', 'not supported', "doesn't support")):
                        self.error = 'Could not warm one or more displays. Check gamma support and other night light apps.'
                        self.report()
                if self.child and self.child.poll() is not None:
                    self.error = self.error or 'Night display stopped unexpectedly. Toggle it off and on to retry.'
                    self.stop()
                    self.report()
        finally:
            self.stop()


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
