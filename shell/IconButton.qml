import QtQuick

Item {
  id: root
  property alias iconSourceSize: glyph.sourceSize
  property alias mirrorIcon: glyph.mirror
  property url iconSource
  property real iconWidth: 14
  property real iconHeight: 14
  property real restingOpacity: 0.6
  property bool animateGlyphOpacity: true
  property int hoverEasing: Easing.OutCubic
  property string accessibleName: ""
  readonly property bool hovered: pointer.containsMouse
  property real glyphOpacity: hovered || activeFocus ? 1 : restingOpacity
  signal clicked
  activeFocusOnTab: enabled
  Accessible.role: Accessible.Button
  Accessible.name: accessibleName
  Accessible.onPressAction: if (enabled) clicked()
  Keys.onReturnPressed: if (enabled) clicked()
  Keys.onEnterPressed: if (enabled) clicked()
  Keys.onSpacePressed: if (enabled) clicked()

  implicitWidth: 24
  implicitHeight: 24
  Rectangle {
    anchors.fill: parent
    radius: 4
    color: "transparent"
    border.width: root.activeFocus ? 1 : 0
    border.color: PanelStyle.accent
  }
  Behavior on glyphOpacity {
    enabled: root.animateGlyphOpacity
    HoverAnimation { easing.type: root.hoverEasing }
  }

  Image {
    id: glyph
    anchors.centerIn: parent
    width: root.iconWidth
    height: root.iconHeight
    source: root.iconSource
    sourceSize: Qt.size(Math.ceil(width * 2), Math.ceil(height * 2))
    fillMode: Image.PreserveAspectFit
    smooth: true
    antialiasing: true
    opacity: root.glyphOpacity
  }

  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
