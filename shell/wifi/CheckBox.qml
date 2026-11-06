import QtQuick
import ".."
import QtQuick.Shapes

Item {
  id: root
  property bool checked: false
  signal toggled(bool checked)
  property string accessibleName: ""
  activeFocusOnTab: enabled
  Accessible.role: Accessible.CheckBox
  Accessible.name: accessibleName
  Accessible.checked: checked
  Accessible.onPressAction: activate()
  Keys.onReturnPressed: activate()
  Keys.onEnterPressed: activate()
  Keys.onSpacePressed: activate()
  function activate() { if (enabled) toggled(!checked); }
  implicitWidth: 24
  implicitHeight: 24

  Rectangle {
    anchors.fill: parent
    radius: 6
    border.width: root.activeFocus ? 1 : 0
    border.color: PanelStyle.accent
    color: checkHover.hovered ? PanelStyle.checkHover : PanelStyle.checkFill
  }

  Shape {
    anchors.centerIn: parent
    width: 20
    height: 20
    visible: root.checked
    ShapePath {
      strokeColor: PanelStyle.checkMark
      strokeWidth: 2
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      fillColor: "transparent"
      startX: 4
      startY: 10
      PathLine { x: 8; y: 14 }
      PathLine { x: 16; y: 6 }
    }
  }

  HoverHandler { id: checkHover; cursorShape: Qt.PointingHandCursor }
  TapHandler { onTapped: root.activate() }
}
