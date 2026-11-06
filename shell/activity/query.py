#!/usr/bin/env python3
"""Read-only activity snapshots. Never infer microphone use from media players."""
import json
import subprocess


def run_json(command):
    result = subprocess.run(command, capture_output=True, text=True, timeout=4, check=True)
    return json.loads(result.stdout)


def streams(objects):
    if not isinstance(objects, list):
        raise ValueError("Invalid PipeWire snapshot")
    nodes = {obj['id']: obj.get('info', {}) for obj in objects
             if obj.get('type') == 'PipeWire:Interface:Node'}
    devices = {obj['id']: obj.get('info', {}).get('props', {}) for obj in objects
               if obj.get('type') == 'PipeWire:Interface:Device'}
    upstream = {}
    for obj in objects:
        if obj.get('type') == 'PipeWire:Interface:Link':
            info = obj.get('info', {})
            upstream.setdefault(info.get('input-node-id'), set()).add(info.get('output-node-id'))
    result = []
    for node_id, info in nodes.items():
        props = info.get('props', {})
        kind = props.get('media.class')
        if kind not in ('Stream/Input/Audio', 'Stream/Output/Audio') or info.get('state') != 'running':
            continue
        capture = kind == 'Stream/Input/Audio'
        sources = [nodes.get(n, {}).get('props', {}) for n in upstream.get(node_id, [])]
        # A sink monitor captures system audio, not a microphone. Virtual sources
        # remain explicitly uncertain; PipeWire cannot identify browser tabs.
        monitor = bool(sources) and all(p.get('media.class') == 'Audio/Sink' for p in sources)
        physical = any(p.get('media.class') == 'Audio/Source' and (p.get('device.api') or devices.get(int(p.get('device.id', -1)), {}).get('device.api')) in ('alsa', 'bluez5') for p in sources)
        muted = next((p['mute'] for p in info.get('params', {}).get('Props', []) if 'mute' in p), None)
        result.append(dict(id=node_id, serial=str(props.get('object.serial', '')),
                           name=props.get('application.name') or props.get('node.description') or props.get('node.name') or 'Unknown app',
                           appId=props.get('application.id', ''),
                           kind='playback' if not capture else 'monitor' if monitor else 'microphone' if physical else 'capture',
                           muted=muted))
    return result


def inhibitors(rows):
    result = []
    for what, who, why, mode, uid, pid in rows:
        if not {'sleep', 'idle'}.intersection(what.split(':')):
            continue
        result.append(dict(name=who or 'Unknown app', reason=why or 'No reason supplied',
                           what=what, mode=mode, pid=pid))
    return result


def snapshot():
    result = dict(streams=[], inhibitors=[], audioError='', sleepError='')
    try:
        result['streams'] = streams(run_json(['pw-dump']))
    except (OSError, ValueError, KeyError, IndexError, TypeError, AttributeError, subprocess.SubprocessError):
        result['audioError'] = 'Audio activity unavailable: PipeWire could not be queried.'
    try:
        data = run_json(['busctl', '--system', '--json=short', 'call', 'org.freedesktop.login1',
                         '/org/freedesktop/login1', 'org.freedesktop.login1.Manager', 'ListInhibitors'])
        result['inhibitors'] = inhibitors(data['data'][0])
    except (OSError, ValueError, KeyError, IndexError, TypeError, AttributeError, subprocess.SubprocessError):
        result['sleepError'] = 'Sleep inhibitors unavailable: logind could not be queried.'
    return result


if __name__ == '__main__':
    print(json.dumps(snapshot()))
