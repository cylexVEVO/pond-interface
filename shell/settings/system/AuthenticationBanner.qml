import QtQuick
import "../../authentication" as Authentication
import "../.." as Shell

Rectangle {
  id: root
  visible: !Authentication.State.registered
  implicitHeight: body.height + 32
  radius: Shell.PanelStyle.radius
  color: Shell.Theme.colors.settingsRow
  Column {
    id: body
    x: 16; y: 16; width: parent.width - 32
    spacing: 12
    Text {
      text: "Pond authentication"
      color: Shell.Theme.colors.text
      font.family: Shell.Theme.titleFontFamily
      font.pixelSize: 20
    }
    Text {
      width: parent.width
      text: Authentication.State.registered ? "System permission requests now use Pond’s dialog."
          : !Authentication.State.available ? "Your Quickshell build is missing Polkit support. Install a Quickshell build with the Polkit module, then check again."
          : "Use Pond’s dialog for system permission requests. Setup disables known desktop authentication agents for your account. You may need to sign out afterward."
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: Shell.Theme.colors.text
      opacity: 0.7
      font.family: Shell.Theme.fontFamily
      font.pixelSize: 13
    }
    Shell.ActionButton {
      visible: !Authentication.State.registered
      width: parent.width
      text: Authentication.State.busy ? "Setting up…" : Authentication.State.available ? "Enable Pond authentication" : "Check again"
      interactive: !Authentication.State.busy
      activeFocusOnTab: interactive
      Accessible.role: Accessible.Button
      Accessible.name: text
      Accessible.onPressAction: if (interactive) clicked()
      Keys.onReturnPressed: if (interactive) clicked()
      Keys.onSpacePressed: if (interactive) clicked()
      border.width: activeFocus ? 1 : 0
      border.color: Shell.PanelStyle.accent
      onClicked: Authentication.State.available ? Authentication.State.enable() : Authentication.State.retry()
    }
    Text {
      width: parent.width
      visible: !!Authentication.State.notice
      text: Authentication.State.notice
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: Shell.Theme.colors.text
      font.family: Shell.Theme.fontFamily
      font.pixelSize: 13
    }
  }
}
