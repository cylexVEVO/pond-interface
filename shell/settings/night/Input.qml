import QtQuick
import "../.." as Shell

Rectangle {
  id: root
  property string title
  property string value
  property string hint
  signal edited(string value)
  height: 51; radius: 12
  color: Shell.Theme.colors.settingsRow
  Text {
    x: 20; anchors.verticalCenter: parent.verticalCenter
    text: root.title; color: Shell.Theme.colors.text; opacity: 0.7
    font.family: Shell.Theme.fontFamily; font.pixelSize: 15
  }
  TextInput {
    id: input
    anchors.right: parent.right; anchors.rightMargin: 20
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width * 0.45
    horizontalAlignment: TextInput.AlignRight
    text: root.value
    color: Shell.Theme.colors.text; selectionColor: Shell.Theme.colors.selection
    font.family: Shell.Theme.fontFamily; font.pixelSize: 15
    activeFocusOnTab: true; selectByMouse: true; clip: true
    Accessible.name: root.title + ". " + root.hint
    onEditingFinished: root.edited(text)
    Text {
      anchors.right: parent.right
      visible: !input.text && !input.activeFocus
      text: root.hint; color: Shell.Theme.colors.text; opacity: 0.4
      font: input.font
    }
  }
}
