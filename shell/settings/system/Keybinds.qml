pragma ComponentBehavior: Bound
import QtQuick
import "." as System
import ".." as Settings
import "../.." as Shell

Settings.Modal {
  id: root
  objectName: "keybindsPanel"
  title: "Keyboard shortcuts"; closeLabel: "Back to System"; bodyTop: 143
  implicitHeight: Math.min(520, availableHeight)
  roundedContent: true
  property string recordingId: ""
  readonly property string query: search.text.trim().toLowerCase()
  readonly property var rows: {
    const items = System.State.shortcuts || [];
    return query ? items.filter(item =>
      (item.title + " " + item.label + " " + item.category).toLowerCase().includes(query)) : items;
  }
  onBackRequested: {
    if (recordingId) recordingId = "";
    else Settings.State.back();
  }
  Keys.onEscapePressed: {
    if (recordingId) recordingId = "";
    else if (search.text) search.clear();
    else Settings.State.back();
  }
  Keys.onPressed: event => {
    if (!recordingId) return;
    event.accepted = true;
    if (event.key === Qt.Key_Escape) { recordingId = ""; return; }
    if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) {
      const id = recordingId; recordingId = "";
      System.State.unbindShortcut(id);
      return;
    }
    const chord = root.chordFromEvent(event);
    if (!chord) return;
    const id = recordingId; recordingId = "";
    System.State.setShortcut(id, chord);
  }

  function beginRecord(item) {
    System.State.error = "";
    recordingId = item.id;
    forceActiveFocus();
  }

  function chordFromEvent(event) {
    const key = event.key;
    if (key === Qt.Key_Control || key === Qt.Key_Shift || key === Qt.Key_Alt || key === Qt.Key_Meta
        || key === Qt.Key_Super_L || key === Qt.Key_Super_R)
      return "";
    const mods = [];
    if (event.modifiers & Qt.MetaModifier) mods.push("Mod");
    if (event.modifiers & Qt.ControlModifier) mods.push("Ctrl");
    if (event.modifiers & Qt.AltModifier) mods.push("Alt");
    if (event.modifiers & Qt.ShiftModifier) mods.push("Shift");
    const trigger = root.triggerName(event);
    if (!trigger) return "";
    return mods.concat([trigger]).join("+");
  }

  function triggerName(event) {
    const key = event.key;
    const named = {};
    named[Qt.Key_Escape] = "Escape";
    named[Qt.Key_Tab] = "TAB";
    named[Qt.Key_Backtab] = "TAB";
    named[Qt.Key_Return] = "Return";
    named[Qt.Key_Enter] = "Return";
    named[Qt.Key_Space] = "Space";
    named[Qt.Key_Home] = "Home";
    named[Qt.Key_End] = "End";
    named[Qt.Key_Left] = "Left";
    named[Qt.Key_Right] = "Right";
    named[Qt.Key_Up] = "Up";
    named[Qt.Key_Down] = "Down";
    named[Qt.Key_Minus] = "Minus";
    named[Qt.Key_Equal] = "equal";
    named[Qt.Key_Plus] = "Plus";
    named[Qt.Key_Comma] = "Comma";
    named[Qt.Key_Period] = "Period";
    named[Qt.Key_Slash] = "Slash";
    if (named[key]) return named[key];
    if (key >= Qt.Key_F1 && key <= Qt.Key_F12) return "F" + (key - Qt.Key_F1 + 1);
    if (key >= Qt.Key_0 && key <= Qt.Key_9) return String.fromCharCode(key);
    if (key >= Qt.Key_A && key <= Qt.Key_Z) return String.fromCharCode(key);
    return "";
  }

  ListView {
    id: list
    objectName: "keybindList"
    x: 16; width: root.width - 32; height: root.scrollItem.height
    bottomMargin: 16
    boundsBehavior: Flickable.StopAtBounds
    model: root.rows
    spacing: 2
    Shell.ScrollWheel { view: list }
    section.property: "category"
    section.delegate: Item {
      required property string section
      width: list.width; height: 34
      Text {
        x: 20; anchors.bottom: parent.bottom; anchors.bottomMargin: 4
        text: parent.section; color: Shell.Theme.colors.text; opacity: 0.35
        font.family: Shell.Theme.fontFamily; font.weight: Font.DemiBold; font.pixelSize: 12
      }
    }
    delegate: Rectangle {
      id: row
      required property var modelData
      required property int index
      readonly property bool recording: root.recordingId === modelData.id
      readonly property bool highlighted: recording || hover.hovered || activeFocus
      width: list.width; height: 50; radius: 12
      color: highlighted ? Shell.PanelStyle.rowHover : "transparent"
      activeFocusOnTab: true
      Accessible.role: Accessible.Button
      Accessible.name: modelData.title + ", " + (recording ? "press a key" : modelData.label)
      Accessible.onPressAction: root.beginRecord(modelData)
      Keys.onReturnPressed: root.beginRecord(modelData)
      Keys.onSpacePressed: root.beginRecord(modelData)

      Text {
        x: 20; width: parent.width - chordBox.width - resetBtn.width - 56
        anchors.verticalCenter: parent.verticalCenter
        text: row.modelData.title; elide: Text.ElideRight
        color: Shell.Theme.colors.text; opacity: 0.7
        font.family: Shell.Theme.fontFamily; font.pixelSize: 15
      }
      Rectangle {
        id: resetBtn
        visible: row.modelData.customized && !row.recording
        anchors.right: chordBox.left; anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        width: visible ? 56 : 0; height: 28; radius: 6
        color: resetHover.hovered ? Shell.PanelStyle.controlHover : "transparent"
        border.width: visible && !resetHover.hovered ? 1 : 0; border.color: Shell.PanelStyle.outline
        Text {
          anchors.centerIn: parent
          text: "Reset"; color: Shell.Theme.colors.text; opacity: 0.6
          font.family: Shell.Theme.fontFamily; font.pixelSize: 12
        }
        HoverHandler { id: resetHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: System.State.resetShortcut(row.modelData.id) }
      }
      Rectangle {
        id: chordBox
        anchors.right: parent.right; anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(72, chordLabel.implicitWidth + 24); height: 32; radius: 8
        color: row.recording ? Shell.PanelStyle.controlHover : "transparent"
        border.width: row.recording ? 0 : 1; border.color: Shell.PanelStyle.outline
        Text {
          id: chordLabel
          anchors.centerIn: parent
          text: row.recording ? "Press keys…" : row.modelData.label
          color: Shell.Theme.colors.text
          opacity: row.recording || row.modelData.unbound ? 0.45 : 0.7
          font.family: Shell.Theme.fontFamily; font.pixelSize: 13
        }
      }
      HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
      TapHandler { onTapped: root.beginRecord(row.modelData) }
    }
  }

  overlay: [
    Rectangle {
      objectName: "keybindSearch"
      x: 30; y: 82; width: root.width - 60 - (resetAll.visible ? 76 : 0); height: 51; radius: 12
      color: search.activeFocus ? Shell.PanelStyle.controlHover : Shell.PanelStyle.controlFill
      HoverHandler { cursorShape: Qt.IBeamCursor }
      TapHandler { onTapped: search.forceActiveFocus() }
      Text {
        x: 20; anchors.verticalCenter: parent.verticalCenter
        visible: !search.text; text: "Search shortcuts"
        color: Shell.Theme.colors.text; opacity: 0.2
        font.family: Shell.Theme.fontFamily; font.pixelSize: 15
      }
      TextInput {
        id: search
        x: 20; width: parent.width - 40; anchors.verticalCenter: parent.verticalCenter
        clip: true; color: Shell.Theme.colors.text
        selectionColor: Shell.PanelStyle.accentText; selectedTextColor: Shell.Theme.colors.text
        font.family: Shell.Theme.fontFamily; font.pixelSize: 15
        Accessible.role: Accessible.EditableText
        Accessible.name: "Search shortcuts"
      }
    },
    Rectangle {
      id: resetAll
      objectName: "keybindResetAll"
      visible: (System.State.shortcuts || []).some(item => item.customized)
      x: root.width - 96; y: 92; width: 66; height: 32; radius: 8
      color: resetAllHover.hovered ? Shell.PanelStyle.rowHover : "transparent"
      border.width: resetAllHover.hovered ? 0 : 1; border.color: Shell.PanelStyle.outline
      Text {
        anchors.centerIn: parent
        text: "Reset all"; color: Shell.Theme.colors.text; opacity: 0.6
        font.family: Shell.Theme.fontFamily; font.pixelSize: 11
      }
      HoverHandler { id: resetAllHover; cursorShape: Qt.PointingHandCursor }
      TapHandler { onTapped: System.State.resetAllShortcuts() }
    },
    Text {
      x: 30; anchors.bottom: parent.bottom; anchors.bottomMargin: 14; width: root.width - 60
      visible: !!System.State.error || !!root.recordingId
      text: root.recordingId
          ? "Press a shortcut…  Delete clears  Esc cancels"
          : System.State.error
      color: root.recordingId ? Shell.Theme.colors.text : "#ffb4ab"
      opacity: root.recordingId ? 0.5 : 1
      wrapMode: Text.Wrap
      font.family: Shell.Theme.fontFamily; font.pixelSize: 12
    }
  ]
}
