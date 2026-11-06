pragma ComponentBehavior: Bound
import QtQuick
import ".." as Shell
import QtQuick.Controls
FocusScope {
  id: root
  property var options: []
  property real maximumHeight: 256
  property string currentValue
  signal selected(string value)
  signal dismissed
  function selectable(option) { return !!option && !option.disabled && !option.separator; }
  function pick(option) { if (enabled && selectable(option)) selected(String(option.value)); }
  function syncSelection() {
    if (!list) return;
    const selected = options.findIndex(o => selectable(o) && String(o.value) === currentValue);
    list.currentIndex = selected >= 0 ? selected : options.findIndex(o => selectable(o));
  }
  onVisibleChanged: if (visible) syncSelection()
  onOptionsChanged: syncSelection()
  onCurrentValueChanged: syncSelection()
  Component.onCompleted: syncSelection()
  width: 276
  height: Math.min(maximumHeight, options.reduce((total, option) => total + (option.separator ? 9 : 40), 16))
  Shell.Shadow { anchors.fill: parent; cornerRadius: 16; shadows: Shell.PanelStyle.controlShadows }
  Rectangle {
    anchors.fill: parent; color: Shell.PanelStyle.menuSurface; radius: 16
    border.width: 0.5; border.color: Shell.PanelStyle.menuBorder
    MouseArea { anchors.fill: parent }
    ListView {
      id: list
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      Shell.ScrollWheel { view: list }
      objectName: "displayOptions"
      x: 8; y: 8; width: parent.width - 16; height: parent.height - 16
      model: root.options
      focus: true; keyNavigationEnabled: true
      currentIndex: -1
      onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
      Component.onCompleted: positionViewAtIndex(currentIndex, ListView.Contain)
      function step(direction) {
        for (let i = currentIndex < 0 ? (direction > 0 ? 0 : count - 1) : currentIndex + direction;
             i >= 0 && i < count; i += direction) {
          if (root.selectable(root.options[i])) { currentIndex = i; return; }
        }
      }
      Keys.onEscapePressed: root.dismissed()
      Keys.onReturnPressed: root.pick(root.options[currentIndex])
      Keys.onEnterPressed: root.pick(root.options[currentIndex])
      Keys.onSpacePressed: root.pick(root.options[currentIndex])
      Keys.onUpPressed: step(-1)
      Keys.onDownPressed: step(1)
      ScrollBar.vertical: ScrollBar { width: 3; policy: ScrollBar.AsNeeded }
      delegate: Rectangle {
        id: option
        required property var modelData
        required property int index
        objectName: "displayOption" + modelData.value
        width: list.width; height: modelData.separator ? 9 : 40; radius: 12
        color: root.selectable(modelData) && (hover.hovered || (list.activeFocus && list.currentIndex === index) || String(modelData.value) === root.currentValue) ? Shell.PanelStyle.menuRowHover : "transparent"
        Accessible.role: modelData.separator ? Accessible.Separator : Accessible.MenuItem; Accessible.name: modelData.label || ""
        Accessible.checked: !!modelData.checked
        Accessible.onPressAction: root.pick(modelData)
        Text {
          x: 12; width: parent.width - (trailing.visible ? 52 : 24); anchors.verticalCenter: parent.verticalCenter
          text: option.modelData.label || ""; elide: Text.ElideRight
          color: Shell.Theme.colors.text; opacity: option.modelData.disabled ? 0.3 : 1
          font.family: Shell.Theme.fontFamily; font.pixelSize: 13; font.weight: Font.Medium
        }
        Image {
          id: trailing
          visible: !!option.modelData.submenu || !!option.modelData.checked
          x: parent.width - 28; anchors.verticalCenter: parent.verticalCenter
          width: 16; height: 16; sourceSize: Qt.size(32, 32)
          rotation: option.modelData.submenu ? -90 : 0
          source: Qt.resolvedUrl(option.modelData.submenu ? "../assets/appearance/chevron.svg" : "../assets/installs/check.svg")
        }
        Rectangle {
          visible: !!option.modelData.separator
          anchors.centerIn: parent
          width: parent.width - 24; height: 1
          color: Shell.Theme.sidebarDivider
        }
        HoverHandler { id: hover; cursorShape: root.selectable(option.modelData) ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { onTapped: root.pick(option.modelData) }
      }
    }
  }
}
