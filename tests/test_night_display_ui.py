"""Offscreen tests of the night page, with inert shell services."""
import os
from pathlib import Path
import shutil
import tempfile
import unittest

os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
try:
    from PySide6.QtCore import QUrl, QObject, Qt
    from PySide6.QtGui import QGuiApplication
    from PySide6.QtQml import QQmlComponent, QQmlEngine
    from PySide6.QtQuick import QQuickWindow
    from PySide6.QtTest import QTest
except ImportError:
    QGuiApplication = None

SHELL = Path(__file__).resolve().parents[1] / 'shell'


@unittest.skipIf(QGuiApplication is None, 'requires PySide6')
class NightDisplayUI(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])

    def test_controls_and_schedule_fields(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            (base / 'settings/night').mkdir(parents=True)
            shutil.copytree(SHELL / 'assets', base / 'assets')
            def write(path, text):
                (base / path).write_text(text)
            for name in ['settings/night/Panel.qml', 'settings/night/Input.qml',
                         'settings/Field.qml', 'Toggle.qml']:
                shutil.copy(SHELL / name, base / name)
            write('qmldir', 'singleton Theme 1.0 Theme.qml\nsingleton PanelStyle 1.0 PanelStyle.qml\n')
            write('Theme.qml', '''pragma Singleton
import QtQuick
QtObject {
 property var colors: ({text: "white", settingsRow: "#222", selection: "blue"})
 property string fontFamily: "Sans"
 property string plexFontFamily: "Sans"
}''')
            write('PanelStyle.qml', '''pragma Singleton
import QtQuick
QtObject {
 property color controlHover: "#333"
 property color accent: "blue"
 property color toggleTrack: "#444"
 property color enabledMark: "white"
 property color enabledSurface: "blue"
}''')
            write('Slider.qml', '''import QtQuick
import QtQuick.Controls
Slider {
 property real externalValue: 0
 property bool showInlineValue: false
 value: externalValue
 from: 0; to: 1
}''')
            write('settings/Modal.qml', '''import QtQuick
Item {
 property string title
 property real contentHeight
 signal backRequested
 width: 580; height: contentHeight
}''')
            write('settings/qmldir', 'singleton State 1.0 State.qml\n')
            write('settings/State.qml', 'pragma Singleton\nimport QtQuick\nQtObject { function back() {} }')
            write('settings/night/qmldir', 'singleton State 1.0 State.qml\n')
            write('settings/night/State.qml', '''pragma Singleton
import QtQuick
QtObject {
 property bool ready: true
 property string error: ""
 property var settings: ({enabled: false, intensity: 0.5, schedule: "manual", start: "20:00", end: "07:00", latitude: "", longitude: ""})
 function update(patch) { settings = Object.assign({}, settings, patch); }
}''')
            engine = QQmlEngine()
            component = QQmlComponent(engine, QUrl.fromLocalFile(str(base / 'settings/night/Panel.qml')))
            root = component.create()
            self.assertIsNotNone(root, '\n'.join(e.toString() for e in component.errors()))
            window = QQuickWindow()
            root.setParentItem(window.contentItem())
            window.resize(600, 900)
            window.show()
            def items(item):
                yield item
                for child in item.childItems():
                    yield from items(child)
            def field(title):
                return next(o for o in items(root) if o is not root and o.property('title') == title)
            def activate(title):
                field(title).forceActiveFocus()
                QTest.keyClick(window, Qt.Key_Space)
                self.app.processEvents()
            self.assertFalse(field('Night display').property('checked'))
            activate('Night display')
            self.assertTrue(field('Night display').property('checked'))
            self.assertFalse(field('Start').isVisible())
            activate('Custom times')
            self.assertTrue(field('Start').isVisible())
            self.assertFalse(field('Latitude').isVisible())
            activate('Sunset to sunrise')
            self.assertFalse(field('Start').isVisible())
            self.assertTrue(field('Latitude').isVisible())
            self.assertTrue(field('Longitude').isVisible())
            window.close()
            root.setParentItem(None)
            root.deleteLater()
            self.app.processEvents()


if __name__ == '__main__':
    unittest.main()
