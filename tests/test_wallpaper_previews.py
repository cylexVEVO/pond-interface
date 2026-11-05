"""Use the wallpaper helper's PyQt6 runtime in a separate process from QML tests."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import unittest

WALLPAPER = Path(__file__).resolve().parents[1] / 'wallpaper'


@unittest.skipIf(importlib.util.find_spec('PyQt6') is None, 'requires PyQt6')
class WallpaperPreviewTests(unittest.TestCase):
    def check(self, code):
        result = subprocess.run([sys.executable, '-c', code], cwd=WALLPAPER,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_every_bundled_wallpaper_has_a_small_readable_preview(self):
        self.check('''
import json
from PyQt6.QtGui import QImageReader
import preview
for entry in json.loads((preview.ROOT / 'catalog.json').read_text()):
    source = preview.INCLUDED / entry['file']
    cached = preview.preview(source)
    assert cached.parent == preview.BUNDLED
    image = QImageReader(str(cached)).read()
    assert not image.isNull()
    assert image.width() <= preview.WIDTH
    assert cached.stat().st_size < source.stat().st_size
''')

    def test_custom_cache_reused_and_invalidated_when_source_changes(self):
        self.check('''
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch
from PyQt6.QtGui import QImage, QColor
import os
import preview
with TemporaryDirectory() as directory:
    root = Path(directory)
    preview.CACHE = root / 'cache'
    source = root / 'custom image.png'
    image = QImage(1920, 1080, QImage.Format.Format_RGB32)
    image.fill(QColor('red'))
    assert image.save(str(source))
    first = preview.preview(source)
    with patch.object(preview, 'generate', side_effect=AssertionError('regenerated cached preview')):
        assert preview.preview(source) == first
    decoded = QImage(str(first))
    assert decoded.width() == 960 and decoded.height() == 540
    stamp = source.stat().st_mtime_ns
    image.fill(QColor('blue'))
    assert image.save(str(source))
    os.utime(source, ns=(stamp + 1000000000, stamp + 1000000000))
    second = preview.preview(source)
    assert second != first
    assert QImage(str(second)).pixelColor(100, 100).blue() > 240
''')

    def test_selection_saves_preview_and_cache_failure_does_not_block_selection(self):
        self.check('''
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch
from PyQt6.QtGui import QImage, QColor
import control
import preview
with TemporaryDirectory() as directory:
    root = Path(directory)
    control.CONFIG = root / 'config'
    preview.CACHE = root / 'cache'
    source = root / 'custom.png'
    image = QImage(128, 64, QImage.Format.Format_RGB32)
    image.fill(QColor('green'))
    assert image.save(str(source))
    with patch.object(control, 'wallpapers', side_effect=control.wallpaper_state):
        saved = control.wallpaper('custom', str(source))
        assert saved['preview'].startswith('file:')
        assert control.wallpaper_state()['preview'] == saved['preview']
        assert control.wallpaper('dynamic')['preview'] == ''
        with patch.object(control, 'preview', side_effect=OSError('read-only cache')):
            assert control.wallpaper('custom', str(source))['preview'] == ''
''')


if __name__ == '__main__':
    unittest.main()
