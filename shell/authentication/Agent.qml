import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Polkit
import ".." as Shell

Scope {
  id: root
  readonly property bool registered: agent.isRegistered
  PolkitAgent { id: agent }

  // Destroy the entire prompt between requests, including any entered secret.
  Loader {
    active: agent.isActive && agent.flow !== null
    sourceComponent: PanelWindow {
      id: window
      readonly property var flow: agent.flow
      property bool details: false
      visible: true
      color: "transparent"
      implicitWidth: 420
      implicitHeight: content.implicitHeight + 48
      WlrLayershell.namespace: "pond-authentication"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
      exclusionMode: ExclusionMode.Ignore

      function submit() {
        if (!flow || !flow.isResponseRequired) return;
        const response = password.text;
        password.text = "";
        password.revealed = false;
        flow.submit(response);
      }
      Connections {
        target: window.flow
        function onIsResponseRequiredChanged() {
          password.text = "";
          password.revealed = false;
          if (window.flow.isResponseRequired) password.focusEditor();
        }
      }
      Shell.PanelBackground {
        anchors.fill: parent
        fill: Shell.PanelStyle.modalGradient
        Column {
          id: content
          x: 24; y: 24; width: parent.width - 48
          spacing: 16
          Text {
            text: "Authentication required"
            color: Shell.Theme.colors.text
            font.family: Shell.Theme.titleFontFamily
            font.pixelSize: 24
            font.styleName: "Book"
          }
          Text {
            width: parent.width
            text: window.flow ? window.flow.message : ""
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Shell.Theme.colors.text
            opacity: 0.75
            font.family: Shell.Theme.fontFamily
            font.pixelSize: 13
            lineHeight: 1.3
          }
          Column {
            width: parent.width
            spacing: 6
            Repeater {
              model: window.flow ? window.flow.identities : []
              Shell.ActionButton {
                required property var modelData
                width: content.width
                text: (window.flow.selectedIdentity === modelData ? "●  " : "○  ") + modelData
                onClicked: {
                  password.text = "";
                  window.flow.selectedIdentity = modelData;
                }
                activeFocusOnTab: true
                Keys.onReturnPressed: clicked()
                Keys.onSpacePressed: clicked()
                border.width: activeFocus ? 1 : 0
                border.color: Shell.PanelStyle.accent
              }
            }
          }
          Shell.Field {
            id: password
            width: parent.width
            visible: window.flow && window.flow.isResponseRequired
            password: !window.flow || !window.flow.responseVisible
            placeholderText: window.flow ? window.flow.inputPrompt : "Password"
            onAccepted: window.submit()
            Component.onCompleted: focusEditor()
          }
          Text {
            width: parent.width
            visible: text.length > 0
            text: window.flow ? window.flow.supplementaryMessage || (window.flow.isResponseRequired ? "" : "Waiting for authentication…") : ""
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Shell.Theme.colors.text
            font.family: Shell.Theme.fontFamily
            font.pixelSize: 13
          }
          Row {
            spacing: 8
            Shell.ActionButton {
              width: (content.width - 8) / 2
              text: "Cancel"
              onClicked: if (window.flow) window.flow.cancelAuthenticationRequest()
              activeFocusOnTab: true
              Keys.onReturnPressed: clicked()
              Keys.onSpacePressed: clicked()
              border.width: activeFocus ? 1 : 0
              border.color: Shell.PanelStyle.accent
            }
            Shell.ActionButton {
              width: (content.width - 8) / 2
              text: "Authenticate"
              interactive: window.flow && window.flow.isResponseRequired
              onClicked: window.submit()
              activeFocusOnTab: interactive
              Keys.onReturnPressed: window.submit()
              Keys.onSpacePressed: window.submit()
              border.width: 1
              border.color: activeFocus ? Shell.PanelStyle.accent : Shell.PanelStyle.outline
            }
          }
          Shell.ActionButton {
            width: parent.width
            text: window.details ? "Hide details" : "Show details"
            onClicked: window.details = !window.details
            activeFocusOnTab: true
            Keys.onReturnPressed: clicked()
            Keys.onSpacePressed: clicked()
            border.width: activeFocus ? 1 : 0
            border.color: Shell.PanelStyle.accent
          }
          Text {
            width: parent.width
            visible: window.details
            text: window.flow ? window.flow.actionId : ""
            textFormat: Text.PlainText
            wrapMode: Text.WrapAnywhere
            color: Shell.Theme.colors.text
            opacity: 0.55
            font.family: Shell.Theme.plexFontFamily
            font.pixelSize: 11
          }
        }
        Keys.onEscapePressed: if (window.flow) window.flow.cancelAuthenticationRequest()
      }
    }
  }
}
