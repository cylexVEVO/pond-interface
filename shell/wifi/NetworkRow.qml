import QtQuick
import ".."

Item {
  id: root
  property var network: ({})
  property bool interactive: true
  property bool busy: false
  signal ethernetToggled(bool checked)
  readonly property bool canDisconnect: !!network.connected && !network.wired
  signal rowClicked
  signal detailsRequested
  signal disconnectClicked
  implicitWidth: PanelStyle.rowWidth
  implicitHeight: PanelStyle.rowHeight

  Rectangle {
    anchors.fill: parent
    radius: PanelStyle.rowRadius
    color: hover.hovered ? PanelStyle.drawerRowHover : "transparent"
  }
  MouseArea {
    anchors.fill: parent
    enabled: root.interactive && !root.network.wired
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: mouse => {
      if (mouse.button === Qt.RightButton)
        root.detailsRequested();
      else
        root.rowClicked();
    }
  }
  SignalIcon {
    visible: !root.network.wired
    x: 12; y: 12; width: 20; height: 20
    bars: Number(root.network.bars || 1)
  }
  Image {
    visible: !!root.network.wired
    x: 12; y: 12; width: 20; height: 20
    source: Qt.resolvedUrl("../assets/wifi/ethernet.svg")
    sourceSize: Qt.size(40, 40)
    fillMode: Image.PreserveAspectFit
  }
  Text {
    x: 40
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: root.network.wired ? -8 : 0
    width: (root.canDisconnect ? 202 : root.network.wired ? 232 : 264) - x
    elide: Text.ElideRight
    text: root.network.wired ? "Ethernet" : String(root.network.ssid || "")
    color: Theme.colors.text
    font.family: Theme.fontFamily
    font.weight: Font.Medium
    font.pixelSize: 13
  }
  Text {
    visible: !!root.network.wired
    x: 40
    y: 25
    width: 232 - x
    elide: Text.ElideRight
    text: (root.network.connected ? "Connected" : "Disconnected") + (root.network.device ? " · " + root.network.device : "")
    color: Theme.colors.text
    opacity: 0.5
    font.family: Theme.fontFamily
    font.pixelSize: 11
  }
  Image {
    visible: !!root.network.locked && !root.network.connected
    x: 272
    anchors.verticalCenter: parent.verticalCenter
    width: 16
    height: 16
    source: Qt.resolvedUrl("../assets/wifi/lock.svg")
  }

  Toggle {
    visible: !!root.network.wired
    x: 238
    anchors.verticalCenter: parent.verticalCenter
    accessibleName: "Ethernet " + (root.network.device || "")
    trackAlpha: PanelStyle.drawerToggleAlpha
    checked: !!root.network.connected
    enabled: root.interactive
    busy: root.busy
    onToggled: checked => root.ethernetToggled(checked)
  }

  Rectangle {
    id: disconnect
    visible: root.canDisconnect
    x: 208
    y: 2
    width: 90
    height: 40
    radius: 10
    color: disconnectHover.hovered ? PanelStyle.controlHover : "transparent"

    Text {
      anchors.centerIn: parent
      text: "Disconnect"
      color: Theme.colors.text
      opacity: disconnectHover.hovered ? 1 : 0.8
      font.family: Theme.fontFamily
      font.weight: Font.Medium
      font.pixelSize: 13
    }
    HoverHandler {
      id: disconnectHover
      enabled: root.interactive
      cursorShape: Qt.PointingHandCursor
    }
    MouseArea {
      anchors.fill: parent
      enabled: root.interactive
      cursorShape: Qt.PointingHandCursor
      onClicked: root.disconnectClicked()
    }
  }
  HoverHandler { id: hover; enabled: root.interactive && !root.network.wired; cursorShape: Qt.PointingHandCursor }
}
