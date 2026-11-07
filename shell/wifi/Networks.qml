pragma ComponentBehavior: Bound
import QtQuick
import "." as Wifi
import ".."

DeviceList {
  id: root
  readonly property bool wifiAvailable: !!Wifi.State.adapter
  readonly property bool canAddNetwork: wifiAvailable && Wifi.State.enabled
  message: Wifi.State.phase === "failed" && Wifi.State._actionKind === "ethernet"
      ? Wifi.State.statusText : ""
  title: "Network"
  viewportHeight: 306
  // Preserve delegates across state updates so toggle animations can finish.
  deviceKey: "key"
  devices: Wifi.State.wiredNetworks.concat(Wifi.State.enabled ? Wifi.State.networks : [])
  emptyText: !Wifi.State.adapter ? "No Wi-Fi adapter found."
      : !Wifi.State.enabled ? "Wi-Fi is off."
      : "No networks found. Move closer to your router and try again."
  headerControl: wifiAvailable ? wifiToggle : null
  Component { id: wifiToggle; Toggle {
    accessibleName: "Wi-Fi"
    trackAlpha: PanelStyle.drawerToggleAlpha
    checked: Wifi.State.enabled
    enabled: root.interactive && !!Wifi.State.adapter
    onToggled: checked => Wifi.State.setWifiEnabled(checked)
  } }
  deviceDelegate: Component { NetworkRow {
    required property var modelData
    width: PanelStyle.rowWidth
    network: modelData
    interactive: root.interactive
    busy: Wifi.State.actionBusy
    onEthernetToggled: checked => Wifi.State.setEthernetEnabled(modelData.device, checked)
    onDisconnectClicked: Wifi.State.disconnect()
    onDetailsRequested: {
      if (modelData.connected || modelData.known)
        root.stackController.push("details", modelData);
    }
    onRowClicked: {
      if (modelData.connected)
        root.stackController.push("details", modelData);
      else if (modelData.locked && !modelData.known)
        root.stackController.push("join", modelData);
      else
        root.stackController.connectNetwork(modelData.ssid, "", false);
    }
  } }
  footer: canAddNetwork ? addNetworkFooter : null
  Component { id: addNetworkFooter; Item {
    id: addNetworkRow
    width: PanelStyle.rowWidth
    height: PanelStyle.rowHeight

    Rectangle {
      anchors.fill: parent
      radius: PanelStyle.rowRadius
      color: addNetworkPointer.containsMouse ? PanelStyle.drawerRowHover
          : Qt.alpha(PanelStyle.drawerRowHover, 0)

      Behavior on color {
        ColorAnimation { duration: PanelStyle.controlDuration }
      }
    }

    Row {
      x: 12
      anchors.verticalCenter: parent.verticalCenter
      spacing: 12
      opacity: addNetworkPointer.containsMouse ? 1 : 0.7
      Image {
        width: 20
        height: 20
        source: Qt.resolvedUrl("../assets/wifi/add.svg")
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "Add a network"
        color: Theme.colors.text
        font.family: Theme.fontFamily
        font.weight: Font.Medium
        font.pixelSize: 15
      }
    }
    MouseArea {
      id: addNetworkPointer
      anchors.fill: parent
      enabled: root.interactive && root.canAddNetwork
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.stackController.push("add", null)
    }
  } }
}
