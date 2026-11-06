pragma ComponentBehavior: Bound
import QtQuick
import "." as System
import ".." as Settings
import "../.." as Shell

Settings.Modal {
  id: root
  property var options: []
  property var selected: []
  property bool multiple: false
  property string placeholder
  signal picked(string id)
  readonly property string query: search.text.trim().toLowerCase()
  readonly property var rows: {
    const pinned = selected.map(id => options.find(option => option.id === id)).filter(Boolean);
    const ordered = pinned.concat(options.filter(option => selected.indexOf(option.id) < 0));
    return query ? ordered.filter(option => (option.search || option.label).toLowerCase().includes(query)) : ordered;
  }
  implicitHeight: Math.min(460, availableHeight)
  bodyTop: 143
  roundedContent: true
  onBackRequested: Settings.State.back()
  Keys.onEscapePressed: { if (search.text) search.clear(); else Settings.State.back(); }
  Keys.onDownPressed: moveSelection(1)
  Keys.onUpPressed: moveSelection(-1)
  Keys.onReturnPressed: chooseCurrent()
  Keys.onEnterPressed: chooseCurrent()
  Component.onCompleted: Qt.callLater(() => search.forceActiveFocus())

  property bool keyboardSelection: false
  function moveSelection(direction) {
    if (!rows.length) return;
    keyboardSelection = true;
    list.currentIndex = Math.max(0, Math.min(rows.length - 1,
        list.currentIndex < 0 ? (direction > 0 ? 0 : rows.length - 1) : list.currentIndex + direction));
    list.positionViewAtIndex(list.currentIndex, ListView.Contain);
  }
  function chooseCurrent() {
    if (list.currentIndex >= 0 && list.currentIndex < rows.length)
      choose(rows[list.currentIndex].id);
  }

  function choose(id) {
    picked(id);
    search.clear();
    search.forceActiveFocus();
  }

  ListView {
    id: list
    objectName: "systemOptions"
    x: 16; width: root.width - 32; height: root.scrollItem.height
    bottomMargin: 16
    boundsBehavior: Flickable.StopAtBounds
    model: root.rows
    currentIndex: -1
    onModelChanged: {
      currentIndex = root.query && root.rows.length ? 0 : -1;
      root.keyboardSelection = false;
      positionViewAtBeginning();
    }
    Shell.ScrollWheel { view: list }
    delegate: Rectangle {
      id: row
      required property var modelData
      required property int index
      readonly property bool chosen: root.selected.indexOf(modelData.id) >= 0
      readonly property bool highlighted: hover.hovered || ((root.keyboardSelection || !!root.query) && list.currentIndex === index)
      width: list.width; height: 50; radius: 12
      color: highlighted ? Shell.PanelStyle.rowHover : "transparent"
      Accessible.role: root.multiple ? Accessible.CheckBox : Accessible.RadioButton
      Accessible.name: modelData.label
      Accessible.checked: chosen
      Accessible.onPressAction: root.choose(modelData.id)
      Text {
        id: offset
        x: 20; anchors.verticalCenter: parent.verticalCenter
        visible: !!text; text: row.modelData.offset || ""
        color: Shell.Theme.colors.text; opacity: 0.4
        font.family: "JetBrains Mono"; font.pixelSize: 14
      }
      Text {
        x: offset.visible ? offset.x + offset.width + 12 : 20
        width: parent.width - x - 64
        anchors.verticalCenter: parent.verticalCenter
        text: row.modelData.label; elide: Text.ElideRight
        color: Shell.Theme.colors.text; opacity: 0.7
        font.family: Shell.Theme.fontFamily; font.pixelSize: 15
      }
      Rectangle {
        visible: root.multiple
        x: parent.width - 44; anchors.verticalCenter: parent.verticalCenter
        width: 24; height: 24; radius: 6
        color: row.highlighted ? Shell.PanelStyle.controlHover : Shell.PanelStyle.controlFill
      }
      Image {
        visible: row.chosen
        x: parent.width - (root.multiple ? 42 : 40); anchors.verticalCenter: parent.verticalCenter
        width: 20; height: 20; sourceSize: Qt.size(40, 40)
        source: Qt.resolvedUrl("../../assets/installs/check.svg")
      }
      HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
      TapHandler { onTapped: root.choose(row.modelData.id) }
    }
  }

  Text {
    x: 30; y: 40; width: root.width - 60
    visible: root.rows.length === 0
    text: root.query ? "No results. Try another search." : "No options available."
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.Wrap
    color: Shell.Theme.colors.text; opacity: 0.6
    font.family: Shell.Theme.fontFamily; font.pixelSize: 15
  }

  overlay: [
    Rectangle {
      objectName: "systemSearch"
      x: 30; y: 82; width: root.width - 60; height: 51; radius: 12
      color: search.activeFocus && !clearHover.hovered ? Shell.PanelStyle.controlHover : Shell.PanelStyle.controlFill
      HoverHandler { cursorShape: Qt.IBeamCursor }
      TapHandler { onTapped: search.forceActiveFocus() }
      Text {
        x: 20; anchors.verticalCenter: parent.verticalCenter
        visible: !search.text; text: root.placeholder
        color: Shell.Theme.colors.text; opacity: 0.2
        font.family: Shell.Theme.fontFamily; font.pixelSize: 15
      }
      TextInput {
        id: search
        x: 20; width: parent.width - 76; anchors.verticalCenter: parent.verticalCenter
        clip: true; color: Shell.Theme.colors.text
        selectionColor: Shell.PanelStyle.accentText; selectedTextColor: Shell.Theme.colors.text
        font.family: Shell.Theme.fontFamily; font.pixelSize: 15
        Accessible.role: Accessible.EditableText
        Accessible.name: root.placeholder
        activeFocusOnTab: true
        cursorDelegate: Rectangle {
          id: caret
          width: 1; color: Shell.PanelStyle.accent
          visible: search.cursorVisible
          Timer {
            running: search.cursorVisible; repeat: true
            interval: Qt.styleHints.cursorFlashTime / 2
            onRunningChanged: caret.opacity = 1
            onTriggered: caret.opacity = 1 - caret.opacity
          }
        }
        Keys.onReturnPressed: root.chooseCurrent()
        Keys.onEnterPressed: root.chooseCurrent()
        Keys.onDownPressed: root.moveSelection(1)
        Keys.onUpPressed: root.moveSelection(-1)
      }
      Image {
        x: parent.width - 36; anchors.verticalCenter: parent.verticalCenter
        width: 20; height: 20; sourceSize: Qt.size(40, 40)
        visible: !search.text
        source: Qt.resolvedUrl("../../assets/search.svg")
      }
      Rectangle {
        objectName: "systemSearchClear"
        x: parent.width - 46; anchors.verticalCenter: parent.verticalCenter
        width: 40; height: 40; radius: 4
        visible: !!search.text
        color: clearHover.hovered || activeFocus ? Shell.PanelStyle.rowHover : "transparent"
        activeFocusOnTab: visible
        Keys.onReturnPressed: { search.clear(); search.forceActiveFocus(); }
        Keys.onEnterPressed: { search.clear(); search.forceActiveFocus(); }
        Keys.onSpacePressed: { search.clear(); search.forceActiveFocus(); }
        Accessible.role: Accessible.Button
        Accessible.name: "Clear search"
        Accessible.onPressAction: search.clear()
        Image {
          anchors.centerIn: parent
          width: 20; height: 20; sourceSize: Qt.size(40, 40)
          source: Qt.resolvedUrl("../../assets/wifi/close.svg")
        }
        HoverHandler { id: clearHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: { search.clear(); search.forceActiveFocus(); } }
      }
    },
    Rectangle {
      objectName: "keyboardShortcut"
      visible: root.multiple && System.State.languageChord !== "None"
      x: root.width - 106; y: 21; width: 76; height: 40; radius: 8
      color: shortcutHover.hovered ? Shell.PanelStyle.rowHover : "transparent"
      border.width: shortcutHover.hovered ? 0 : 1; border.color: Shell.PanelStyle.outline
      Accessible.role: Accessible.StaticText
      Accessible.name: "Shortcut: " + System.State.languageChord + " switches between languages"
      Text {
        anchors.centerIn: parent
        text: "Shortcut"; color: Shell.Theme.colors.text; opacity: shortcutHover.hovered ? 1 : 0.5
        font.family: Shell.Theme.fontFamily; font.weight: Font.DemiBold
        font.pixelSize: 10; font.letterSpacing: 0.1
      }
      HoverHandler { id: shortcutHover }
    },
    Item {
      id: shortcutTip
      objectName: "keyboardShortcutTip"
      readonly property var keys: {
        const chord = System.State.languageChord || "Super+K";
        return chord.split("+").map(part => {
          const lower = part.toLowerCase();
          if (lower === "super" || lower === "mod") return "spr";
          if (lower === "ctrl" || lower === "control") return "ctrl";
          if (lower === "alt") return "alt";
          if (lower === "shift") return "sft";
          return part.length <= 3 ? part.toLowerCase() : part.slice(0, 3).toLowerCase();
        });
      }
      x: root.width + 10; width: Math.max(160, 20 + keys.length * 46); height: 142
      visible: shortcutHover.hovered && System.State.languageChord !== "None"
      Item {
        anchors { fill: parent; margins: -90; bottomMargin: -180 }
        layer.enabled: true
        layer.format: ShaderEffectSource.RGBA16F
        Shell.Shadow {
          anchors { fill: parent; margins: 90; bottomMargin: 180 }
          cornerRadius: 24
          shadows: Shell.PanelStyle.controlShadows.map(s => Object.assign({}, s, { blur: s.blur * 2.4 }))
        }
      }
      Rectangle {
        anchors.fill: parent; radius: 24
        color: Settings.Style.card
        Text {
          x: 20; y: 15; width: parent.width - 40
          text: "Switch between languages"; color: Shell.Theme.colors.text
          wrapMode: Text.WordWrap; lineHeight: 21; lineHeightMode: Text.FixedHeight
          font.family: Shell.Theme.fontFamily; font.weight: Font.Medium; font.pixelSize: 15
        }
        Row {
          x: 20; y: 82; spacing: 6
          Repeater {
            model: shortcutTip.keys
            delegate: Rectangle {
              id: key
              required property string modelData
              required property int index
              width: 40; height: 40; radius: 4
              color: "transparent"; border.color: Qt.rgba(1, 1, 1, 0.15)
              Rectangle {
                anchors.centerIn: parent; width: 32; height: 32; radius: 16
                color: "transparent"; border.color: Qt.rgba(1, 1, 1, 0.15)
              }
              Text {
                anchors.centerIn: parent
                text: key.modelData; color: Shell.Theme.colors.text
                font.family: Shell.Theme.fontFamily
                font.weight: key.index === shortcutTip.keys.length - 1 ? Font.Bold : Font.DemiBold
                font.pixelSize: key.index === shortcutTip.keys.length - 1 ? 12 : 10
              }
            }
          }
        }
      }
    }
  ]
}
