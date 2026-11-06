import QtQuick
import QtQuick.Effects

Item {
  id: root
  signal clicked
  activeFocusOnTab: enabled
  Accessible.role: Accessible.Button
  Accessible.name: "Close"
  Accessible.onPressAction: if (enabled) clicked()
  Keys.onReturnPressed: if (enabled) clicked()
  Keys.onEnterPressed: if (enabled) clicked()
  Keys.onSpacePressed: if (enabled) clicked()
  implicitWidth: 40
  implicitHeight: 40

  Rectangle {
    anchors.fill: parent
    radius: 12
    color: closeHover.hovered ? PanelStyle.closeHover : PanelStyle.closeFill
    border.color: root.activeFocus ? PanelStyle.accent : closeHover.hovered ? PanelStyle.closeHoverBorder : PanelStyle.closeBorder
    border.width: Theme.translucent && !closeHover.hovered && !root.activeFocus ? 0 : 1
    antialiasing: true

    PanelBorder {
      visible: Theme.translucent && !closeHover.hovered
      radius: 12
      color: PanelStyle.closeBorder
    }

    Image {
      anchors.centerIn: parent
      width: 20
      height: 20
      source: Qt.resolvedUrl("assets/wifi/close.svg")
      layer.enabled: Theme.translucent && (closeHover.hovered || !Qt.colorEqual(Theme.colors.closeGlyph, "white"))
      layer.effect: MultiEffect { colorization: 1; colorizationColor: closeHover.hovered ? Theme.colors.closeHoverGlyph : Theme.colors.closeGlyph }
    }
  }

  HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
  TapHandler { onTapped: root.clicked() }
}
