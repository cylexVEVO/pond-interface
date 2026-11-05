"""Run with PySide6 installed and QT_QPA_PLATFORM=offscreen.

Uses Qt's real compiler/incubator; no Quickshell or compositor is required.
"""
import os
from pathlib import Path
import tempfile
import unittest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
try:
    from PySide6.QtCore import QUrl
    from PySide6.QtGui import QGuiApplication
    from PySide6.QtTest import QTest
    from PySide6.QtQml import QQmlComponent, QQmlEngine, QQmlIncubationController
except ImportError:
    QGuiApplication = None


@unittest.skipIf(QGuiApplication is None, "requires PySide6")
class DeferredWindowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.engine = QQmlEngine()
        self.controller = QQmlIncubationController()
        self.engine.setIncubationController(self.controller)
        shell = (Path(__file__).resolve().parents[1] / "shell").as_uri()
        Path(self.temp.name, "Window.qml").write_text('''
import QtQuick
QtObject {
    required property int contextValue
    property int retainedValue: 0
}
''')
        self.component = QQmlComponent(self.engine)
        self.component.setData(('''
import QtQuick
import "%s" as Shell
Item {
    id: root
    property bool requested: false
    property bool preload: false
    property int contextValue: 42
    readonly property bool ready: loader.status === Loader.Ready
    readonly property bool settled: loader.settled
    readonly property bool loading: loader.status === Loader.Loading
    readonly property var loaded: loader.item
    Shell.DeferredWindow {
        id: loader
        requested: root.requested
        preload: root.preload
        windowSource: Qt.resolvedUrl("Window.qml")
        initialProperties: ({contextValue: Qt.binding(() => root.contextValue)})
    }
}
''' % shell).encode(), QUrl.fromLocalFile(str(Path(self.temp.name, "Host.qml"))))
        self.assertTrue(self.component.isReady(), [e.toString() for e in self.component.errors()])

    def create(self, **properties):
        self.root = self.component.createWithInitialProperties(properties)
        self.assertIsNotNone(self.root, [e.toString() for e in self.component.errors()])
        return self.root

    def drain(self):
        for _ in range(1000):
            QTest.qWait(1)
            self.controller.incubateFor(1)
            if self.root.property("settled"):
                return
        self.fail("preload never settled")

    def test_no_work_before_first_frame_trigger(self):
        root = self.create()
        for _ in range(10):
            self.app.processEvents()
            self.controller.incubateFor(1)
        self.assertFalse(root.property("ready"))
        self.assertFalse(root.property("loading"))
        self.assertIsNone(root.property("loaded"))

    def test_background_preload_preserves_required_property_binding(self):
        root = self.create()
        root.setProperty("preload", True)
        self.drain()
        self.assertTrue(root.property("ready"))
        loaded = root.property("loaded")
        self.assertEqual(loaded.property("contextValue"), 42)
        root.setProperty("contextValue", 73)
        self.assertEqual(loaded.property("contextValue"), 73)

    def test_request_before_first_frame_loads_immediately(self):
        root = self.create(requested=True)
        self.assertTrue(root.property("ready"))

    def test_request_finishes_inflight_preload_and_retains_window(self):
        root = self.create(preload=True)
        # Source compilation can be asynchronous; leave incubation unfinished.
        for _ in range(1000):
            QTest.qWait(1)
            if self.controller.incubatingObjectCount():
                break
        self.assertTrue(root.property("loading"))
        root.setProperty("requested", True)
        self.assertTrue(root.property("ready"))
        loaded = root.property("loaded")
        loaded.setProperty("retainedValue", 91)
        root.setProperty("requested", False)
        root.setProperty("preload", False)
        self.app.processEvents()
        root.setProperty("requested", True)
        self.assertEqual(root.property("loaded").property("retainedValue"), 91)


if __name__ == "__main__":
    unittest.main()
