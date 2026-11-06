"""Offscreen interaction tests for real QML controls with inert theme/services.

Run with PySide6 installed; no compositor or Quickshell services are needed.
"""
import os
from pathlib import Path
import shutil
import tempfile
import unittest

os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
try:
    from PySide6.QtCore import QUrl, Qt, QPoint, QObject
    from PySide6.QtGui import QGuiApplication
    from PySide6.QtQml import QQmlComponent, QQmlEngine
    from PySide6.QtQuick import QQuickWindow
    from PySide6.QtTest import QTest
except ImportError:
    QGuiApplication = None

SHELL = Path(__file__).resolve().parents[1] / 'shell'


@unittest.skipIf(QGuiApplication is None, 'requires PySide6')
class UIControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name)
        for name in ('settings/system', 'wifi'):
            (self.base / name).mkdir(parents=True)
        for name in ('IconButton.qml', 'HoverAnimation.qml', 'Toggle.qml',
                     'ScrollWheel.qml', 'settings/Field.qml', 'settings/Dropdown.qml',
                     'settings/system/Picker.qml', 'wifi/CheckBox.qml', 'Field.qml',
                     'wifi/Join.qml', 'wifi/AddNetwork.qml', 'wifi/SelectField.qml',
                     'wifi/FormViewport.qml', 'wifi/SecurityMenu.qml'):
            shutil.copy(SHELL / name, self.base / name)
        shutil.copytree(SHELL / 'assets', self.base / 'assets')
        self.write('qmldir', 'singleton Theme 1.0 Theme.qml\nsingleton PanelStyle 1.0 PanelStyle.qml\n')
        self.write('Theme.qml', '''pragma Singleton
import QtQuick
QtObject {
 property var colors: ({text: "white", settingsRow: "#222222"})
 property string titleFontFamily: "Sans"
 property string fontFamily: "Sans"
 property string plexFontFamily: "Monospace"
 property color sidebarDivider: "gray"
}''')
        colors = ['accent', 'enabledMark', 'enabledSurface', 'controlHover',
                  'rowHover', 'menuSurface', 'menuBorder', 'menuRowHover',
                  'controlFill', 'accentText', 'outline', 'checkHover', 'checkFill', 'checkMark',
                  'drawerHover', 'drawerFill', 'fieldFocus', 'selectFill']
        self.write('PanelStyle.qml', 'pragma Singleton\nimport QtQuick\nQtObject {\n'
                   + '\n'.join('property color %s: "gray"' % name for name in colors)
                   + '\nproperty var controlShadows: []\n'
                   + 'property int fieldWidth: 276; property int fieldHeight: 44; property int rowRadius: 12; '
                   + 'property int width: 316; property int openDuration: 0; property int controlDuration: 0\n}')
        self.write('Shadow.qml', 'import QtQuick\nItem { property real cornerRadius; property var shadows }')
        self.write('PanelBackground.qml', 'import QtQuick\nItem { property bool stacked }')
        self.write('wifi/EnterpriseFields.qml', '''import QtQuick
Item {
 property bool complete: false
 property string secret: ""
 property var settings: ({})
 signal fieldFocused(var field)
 signal accepted()
 signal menuRequested(var menu)
 function focusEditor() {}
 function select(setting, mode) {}
}''')
        self.write('settings/qmldir', 'singleton State 1.0 State.qml\n')
        self.write('settings/State.qml', 'pragma Singleton\nimport QtQuick\nQtObject { function back() {} }')
        self.write('settings/system/qmldir', 'singleton State 1.0 State.qml\n')
        self.write('settings/system/State.qml', 'pragma Singleton\nimport QtQuick\nQtObject { property string languageChord: "None" }')
        self.write('settings/Modal.qml', '''import QtQuick
Item {
 property real availableHeight: 900
 property real bodyTop: 0
 property bool roundedContent: false
 property alias scrollItem: viewport
 property alias overlay: overlays.data
 signal backRequested()
 width: 580
 Item { id: viewport; height: parent.height - parent.bodyTop }
 Item { id: overlays; anchors.fill: parent }
}''')
        self.engine = QQmlEngine()
        self.window = QQuickWindow()
        self.window.resize(600, 500)
        self.window.show()

    def write(self, name, text):
        (self.base / name).write_text(text)

    def create(self, source):
        self.component = QQmlComponent(self.engine)
        self.component.setData(source.encode(), QUrl.fromLocalFile(str(self.base / 'Test.qml')))
        self.assertTrue(self.component.isReady(), [e.toString() for e in self.component.errors()])
        self.root = self.component.create()
        self.assertIsNotNone(self.root)
        self.root.setParentItem(self.window.contentItem())
        self.root.forceActiveFocus()
        QTest.qWait(20)
        return self.root

    def tearDown(self):
        self.window.close()
        if hasattr(self, 'root'):
            self.root.setParentItem(None)
            self.root.deleteLater()
        self.window.deleteLater()
        self.engine.deleteLater()
        self.app.processEvents()
        self.temp.cleanup()

    def test_icon_keyboard_activation_once_and_disabled(self):
        root = self.create('''import QtQuick
IconButton { property int clicks: 0; onClicked: clicks++ }''')
        for key in (Qt.Key_Return, Qt.Key_Enter, Qt.Key_Space):
            QTest.keyClick(self.window, key)
        self.assertEqual(root.property('clicks'), 3)
        root.setProperty('enabled', False)
        QTest.keyClick(self.window, Qt.Key_Space)
        self.assertEqual(root.property('clicks'), 3)

    def test_toggle_does_not_activate_while_busy(self):
        root = self.create('''import QtQuick
Toggle { property int changes: 0; onToggled: value => { changes++; checked = value; } }''')
        QTest.keyClick(self.window, Qt.Key_Space)
        self.assertTrue(root.property('checked'))
        root.setProperty('busy', True)
        QTest.keyClick(self.window, Qt.Key_Space)
        self.assertEqual(root.property('changes'), 1)

    def test_settings_switch_row_and_thumb_each_toggle_once(self):
        root = self.create('''import QtQuick
import "settings" as Settings
Settings.Field { title: "Example"; value: ""; toggle: true
 property int changes: 0; onToggled: value => { changes++; checked = value; }
}''')
        for point in (QPoint(80, 25), QPoint(475, 25)):
            before = root.property('changes')
            QTest.mouseClick(self.window, Qt.LeftButton, pos=point)
            self.assertEqual(root.property('changes'), before + 1)
        QTest.keyClick(self.window, Qt.Key_Return)
        self.assertEqual(root.property('changes'), 3)

    def test_dropdown_skips_separators_disabled_and_edges(self):
        root = self.create('''import QtQuick
import "settings" as Settings
Settings.Dropdown {
 options: [{separator:true}, {value:"a", label:"A"}, {separator:true},
           {value:"blocked", label:"Blocked", disabled:true}, {value:"b", label:"B"}, {separator:true}]
 currentValue: "a"
 property string picked: ""
 onSelected: value => picked = value
}''')
        for key in (Qt.Key_Down, Qt.Key_Down, Qt.Key_Return):
            QTest.keyClick(self.window, key)
        self.assertEqual(root.property('picked'), 'b')
        for key in (Qt.Key_Up, Qt.Key_Up, Qt.Key_Enter):
            QTest.keyClick(self.window, key)
        self.assertEqual(root.property('picked'), 'a')
        root.setProperty('currentValue', 'b')
        QTest.keyClick(self.window, Qt.Key_Return)
        self.assertEqual(root.property('picked'), 'b')
        root.setProperty('options', [])
        QTest.keyClick(self.window, Qt.Key_Return)
        self.assertEqual(root.property('picked'), 'b')

    def test_picker_arrow_navigation_selects_result(self):
        root = self.create('''import QtQuick
import "settings/system" as System
System.Picker {
 options: [{id:"a",label:"Alpha"},{id:"b",label:"Beta"}]
 placeholder: "Search"
 property string chosen: ""
 property int picks: 0
 onPicked: id => { chosen = id; picks++; }
}''')
        for key in (Qt.Key_Down, Qt.Key_Down, Qt.Key_Return):
            QTest.keyClick(self.window, key)
        self.assertEqual(root.property('chosen'), 'b')
        self.assertEqual(root.property('picks'), 1)
        root.setProperty('options', [])
        QTest.keyClick(self.window, Qt.Key_Down)
        QTest.keyClick(self.window, Qt.Key_Return)
        self.assertEqual(root.property('chosen'), 'b')

    def test_join_keeps_height_and_gates_connect(self):
        root = self.create('''import QtQuick
import "wifi" as Wifi
Wifi.Join {
 selection: ({ssid:"Example"})
 property int connections: 0
 stackController: QtObject { function connectNetwork() { connections++; } }
}''')
        initial_height = root.property('implicitHeight')
        editor = next(child for child in root.findChildren(QObject)
                      if child.metaObject().className().startswith('QQuickTextInput'))
        editor.forceActiveFocus()
        QTest.keyClick(self.window, Qt.Key_Return)
        self.assertEqual(root.property('connections'), 0)
        editor.setProperty('text', 'password')
        QTest.qWait(20)
        self.assertEqual(root.property('implicitHeight'), initial_height)
        QTest.keyClick(self.window, Qt.Key_Return)
        self.assertEqual(root.property('connections'), 1)
        root.setProperty('interactive', False)
        QTest.keyClick(self.window, Qt.Key_Return)
        self.assertEqual(root.property('connections'), 1)

    def test_add_network_keeps_height_when_form_becomes_complete(self):
        root = self.create('''import QtQuick
import "wifi" as Wifi
Wifi.AddNetwork { }''')
        initial_height = root.property('implicitHeight')
        for child in root.findChildren(QObject):
            if child.metaObject().className().startswith('QQuickTextInput'):
                child.setProperty('text', 'example')
        QTest.qWait(20)
        self.assertTrue(root.property('canConnect'))
        self.assertEqual(root.property('implicitHeight'), initial_height)
