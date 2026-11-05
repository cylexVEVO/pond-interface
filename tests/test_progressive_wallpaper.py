"""Exercise the real Qt image-loading and rendering path offscreen."""
import os
from pathlib import Path
import threading
import unittest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
try:
    from PySide6.QtCore import QUrl
    from PySide6.QtGui import QGuiApplication, QImage, QColor
    from PySide6.QtQuick import QQuickView, QQuickImageProvider
    from PySide6.QtTest import QTest
except ImportError:
    QGuiApplication = None


if QGuiApplication:
    class Images(QQuickImageProvider):
        def __init__(self):
            super().__init__(QQuickImageProvider.Image)
            self.release = threading.Event()
            self.requests = []

        def requestImage(self, name, size, requested):
            self.requests.append((name, requested.width(), requested.height()))
            if name == 'detail':
                self.release.wait(5)
            image = QImage(96, 64, QImage.Format_RGB32)
            image.fill(QColor('blue' if name == 'detail' else 'green'))
            size.setWidth(image.width())
            size.setHeight(image.height())
            return image


@unittest.skipIf(QGuiApplication is None, 'requires PySide6')
class ProgressiveWallpaperTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])

    def setUp(self):
        self.provider = Images()
        self.view = QQuickView()
        self.view.engine().addImageProvider('test', self.provider)
        self.view.setResizeMode(QQuickView.SizeRootObjectToView)
        self.view.setInitialProperties({'source': 'image://test/detail',
                                        'previewSource': 'image://test/preview'})
        self.view.setSource(QUrl.fromLocalFile(str(
            Path(__file__).resolve().parents[1] / 'wallpaper/desktop/ProgressiveImage.qml')))
        self.assertFalse(self.view.errors(), self.view.errors())
        self.root = self.view.rootObject()

    def tearDown(self):
        self.provider.release.set()
        self.view.close()
        QTest.qWait(30)
        self.view.deleteLater()
        self.app.processEvents()

    def wait_until(self, predicate):
        for _ in range(100):
            if predicate():
                return
            QTest.qWait(10)
        self.fail('image did not reach expected state')

    def test_preview_is_visible_while_full_image_is_stalled(self):
        self.view.resize(640, 360)
        self.view.show()
        self.wait_until(lambda: any(r[0] == 'detail' for r in self.provider.requests))
        QTest.qWait(30)
        image = self.view.grabWindow()
        self.assertFalse(image.isNull())
        self.assertEqual(image.pixelColor(320, 180).name(), QColor('green').name())
        self.assertEqual(self.provider.requests[0][0], 'preview')
        self.assertEqual(self.provider.requests[1], ('detail', 640, 360))
        self.provider.release.set()
        detail = self.root.findChild(object, 'wallpaperImage')
        self.wait_until(lambda: detail.property('visible'))
        QTest.qWait(30)
        self.assertEqual(self.view.grabWindow().pixelColor(320, 180).name(), QColor('blue').name())

    def test_no_native_resolution_decode_before_geometry(self):
        QTest.qWait(30)
        self.assertEqual(self.provider.requests, [])

    def test_missing_preview_falls_back_to_full_image(self):
        self.root.setProperty('previewSource', QUrl.fromLocalFile('/missing-wallpaper-preview.jpg'))
        self.provider.release.set()
        self.view.resize(640, 360)
        self.view.show()
        self.wait_until(lambda: self.root.property('ready'))
        self.assertEqual(self.provider.requests, [('detail', 640, 360)])


if __name__ == '__main__':
    unittest.main()
