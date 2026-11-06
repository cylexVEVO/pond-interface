import importlib.util
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('activity', ROOT / 'shell/activity/query.py')
activity = importlib.util.module_from_spec(spec)
spec.loader.exec_module(activity)


def node(number, media_class, state='running', **props):
    return {'id': number, 'type': 'PipeWire:Interface:Node',
            'info': {'state': state, 'props': {'media.class': media_class, **props}}}


def link(source, target):
    return {'type': 'PipeWire:Interface:Link',
            'info': {'output-node-id': source, 'input-node-id': target}}


class ActivityTests(unittest.TestCase):
    def test_capture_distinguishes_microphone_monitor_and_unknown(self):
        objects = [node(1, 'Audio/Source', **{'device.id': 20}), node(2, 'Audio/Sink'),
                   node(3, 'Stream/Input/Audio', **{'application.name': 'Recorder'}),
                   node(4, 'Stream/Input/Audio'), node(5, 'Stream/Input/Audio'),
                   link(1, 3), link(2, 4),
                   {'id': 20, 'type': 'PipeWire:Interface:Device',
                    'info': {'props': {'device.api': 'alsa'}}}]
        streams = activity.streams(objects)
        self.assertEqual([s['kind'] for s in streams], ['microphone', 'monitor', 'capture'])
        self.assertEqual(streams[0]['name'], 'Recorder')
        self.assertEqual(streams[2]['name'], 'Unknown app')

    def test_only_running_audio_streams_and_preserve_mute(self):
        playing = node(1, 'Stream/Output/Audio')
        playing['info']['params'] = {'Props': [{'mute': True}]}
        streams = activity.streams([playing, node(2, 'Stream/Output/Audio', 'idle'),
                                    node(3, 'Stream/Output/Video'), node(4, 'Audio/Source')])
        self.assertEqual(len(streams), 1)
        self.assertEqual(streams[0]['kind'], 'playback')
        self.assertTrue(streams[0]['muted'])

    def test_camera_is_distinguished_from_screen_and_unknown_video(self):
        objects = [node(1, 'Video/Source', **{'device.api': 'v4l2'}),
                   node(2, 'Video/Source', **{'media.role': 'Screen'}),
                   node(3, 'Stream/Input/Video'), node(4, 'Stream/Input/Video'),
                   node(5, 'Stream/Input/Video'), link(1, 3), link(2, 4)]
        self.assertEqual([s['kind'] for s in activity.streams(objects)],
                         ['camera', 'screen', 'video'])

    def test_sleep_delays_are_not_conflated_with_blockers(self):
        rows = [('sleep', 'Pond', 'Lock before sleep', 'delay', 1000, 1),
                ('idle:sleep', 'Slides', 'Presenting', 'block', 1000, 2),
                ('handle-lid-switch', 'Power manager', '', 'block', 1000, 3)]
        result = activity.inhibitors(rows)
        self.assertEqual([i['mode'] for i in result], ['delay', 'block'])
        self.assertEqual(result[0]['reason'], 'Lock before sleep')

    def test_audio_failure_does_not_hide_successful_sleep_query(self):
        with patch.object(activity, 'run_json', side_effect=[FileNotFoundError(),
                {'data': [[['sleep', 'App', 'Saving', 'delay', 1000, 7]]]}]):
            result = activity.snapshot()
        self.assertTrue(result['audioError'])
        self.assertFalse(result['sleepError'])
        self.assertEqual(result['inhibitors'][0]['name'], 'App')

    def test_empty_is_different_from_unavailable(self):
        with patch.object(activity, 'run_json', side_effect=[[], {'data': [[]]}]):
            result = activity.snapshot()
        self.assertFalse(result['audioError'])
        self.assertFalse(result['sleepError'])
        with patch.object(activity, 'run_json', side_effect=subprocess.TimeoutExpired('query', 4)):
            result = activity.snapshot()
        self.assertTrue(result['audioError'])
        self.assertTrue(result['sleepError'])

    def test_malformed_snapshot_is_not_reported_as_no_activity(self):
        with patch.object(activity, 'run_json', side_effect=[{}, {}]):
            result = activity.snapshot()
        self.assertTrue(result['audioError'])
        self.assertTrue(result['sleepError'])
