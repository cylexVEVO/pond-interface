import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Wayland
import "audio" as Audio
import "bluetooth" as Bluetooth
import "settings" as Settings
import "calendar" as Calendar
import "media" as Media
import "minimap" as Minimap
import "notifications" as Notifications
import "installs" as Installs
import "activity" as Activity
import "battery" as Battery
import Pond.Screenshot as Screenshot

PanelWindow {
  id: root
  // Start optional UI work only after a frame has reached the compositor.
  property bool firstFramePresented: false
  readonly property bool panelsReady: bluetoothPanel.settled
  Item {
    id: frameObserver
    Connections {
      target: frameObserver.Window.window
      enabled: !root.firstFramePresented
      function onFrameSwapped() { root.firstFramePresented = true; }
    }
  }

  required property bool expanded
  property string popup: ""
  property real collapseProgress: expanded ? 0 : 1
  signal toggleRequested
  readonly property real cardWidth: Theme.lerp(Theme.sidebarCardExpandedWidth,
      Theme.sidebarCardCollapsedWidth, Theme.collapseWidth(collapseProgress))

  readonly property real panelX: Theme.sidebarOuterMargin + cardWidth + Theme.sidebarCardGap
  readonly property bool panelOpen: wifiPanel.opened || audioPanel.opened || bluetoothPanel.opened
  readonly property var activePanel: wifiPanel.opened ? wifiPanel : audioPanel.opened ? audioPanel : bluetoothPanel.opened ? bluetoothPanel : null
  property string pendingPanel: ""
  readonly property var panels: ({wifi: wifiPanel, audio: audioPanel, bluetooth: bluetoothPanel})

  function dismissPanels() {
    panelSwitchDelay.stop();
    pendingPanel = "";
    for (const panel of Object.values(panels)) panel.closeAll();
  }

  function togglePanel(name) {
    const panel = panels[name];
    if (!panel) return;
    const wasOpen = panel.opened;
    const wasVisible = Object.values(panels).some(item => item.presented);
    dismissPanels();
    if (wasOpen) return;
    Settings.State.close();
    popup = "";
    Notifications.State.closePanel();
    if (wasVisible) {
      pendingPanel = name;
      panelSwitchDelay.restart();
    } else panel.open();
  }

  function togglePopup(name) {
    dismissPanels();
    Notifications.State.closePanel();
    popup = popup === name ? "" : name;
  }

  Timer {
    id: panelSwitchDelay
    interval: 200
    onTriggered: {
      const panel = root.panels[root.pendingPanel];
      if (panel) panel.open();
      root.pendingPanel = "";
    }
  }

  Connections {
    target: Settings.State
    function onOpening() {
      root.dismissPanels();
      root.popup = "";
      Notifications.State.closePanel();
    }
  }
  Connections {
    target: Notifications.State
    function onPanelOpenChanged() {
      if (Notifications.State.panelOpen) {
        root.dismissPanels();
        root.popup = "";
      }
    }
  }
  Connections {
    target: Bluetooth.State
    function onPanelCommand(command, outputName) {
      if (outputName !== root.screen.name) return;
      if (command === "close") bluetoothPanel.closeAll();
      else if (command === "toggle" || !bluetoothPanel.opened) root.togglePanel("bluetooth");
    }
  }
  Connections {
    target: Audio.State
    function onKeyboardOutputVolumeChanged(value) {
      if (NiriMsg.focusedOutputName === "" || root.screen.name === NiriMsg.focusedOutputName)
        controls.showKeyboardVolume();
    }
  }

  color: "transparent"
  BackgroundEffect.blurRegion: Theme.translucent && !Zen.active ? cardBlur : null
  onHeightChanged: cardBlur.changed()
  Region {
    id: cardBlur
    regions: [timeCard.blurRegion, workspacesCard.blurRegion, mediaCard.blurRegion,
      installsCard.blurRegion, controls.blurRegion,
      wifiPanel.blurRegion, audioPanel.blurRegion, bluetoothPanel.blurRegion].filter(Boolean)
  }
  // Keep compositor resizes out of the card animation; only the input area shrinks.
  implicitWidth: Math.ceil(Math.max(Theme.sidebarOuterMargin + Theme.sidebarCardExpandedWidth + Theme.sidebarFadeWidth,
      wifiPanel.presented ? panelX + wifiPanel.width + 67 : 0,
      audioPanel.presented ? panelX + audioPanel.width + 67 : 0,
      bluetoothPanel.presented ? panelX + bluetoothPanel.width + 67 : 0))
  mask: Region {
    width: Zen.active ? 36 : root.panelOpen ? root.implicitWidth : Math.ceil(Theme.sidebarOuterMargin + Math.max(root.cardWidth,
        workspacesCard.width, mediaCard.width, controls.width) + 8)
    height: Zen.active ? zenControls.y + zenControls.height : root.height
    // Let the background receive clicks between the card stacks.
    Region {
      y: Math.ceil(mainStack.y + mainStack.height)
      width: root.width
      height: Zen.active ? 0 : Math.max(0, Math.floor(bottomStack.y) - y)
      intersection: Intersection.Subtract
    }
    // Region.item can retain the opening animation's scaled bounds and leave
    // the close button outside the input mask. Track the panel bounds directly.
    Region {
      x: root.activePanel ? root.activePanel.x : 0
      y: root.activePanel ? root.activePanel.y : 0
      width: root.activePanel ? root.activePanel.width : 0
      height: root.activePanel ? root.activePanel.height : 0
    }
  }
  anchors { left: true; top: true; bottom: true }
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.namespace: "pond-sidebar"
  WlrLayershell.keyboardFocus: workspacesCard.dragSession.active
      ? WlrKeyboardFocus.Exclusive : panelOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
  WlrLayershell.exclusionMode: ExclusionMode.Normal
  exclusiveZone: Zen.active ? 0 : Theme.sidebarOuterMargin + (expanded
      ? Theme.sidebarCardExpandedWidth : Theme.sidebarCardCollapsedWidth)
  Behavior on collapseProgress { Motion {} }

  Connections {
    target: Zen
    function onActiveChanged() { root.dismissPanels(); root.popup = ""; }
  }
  Column {
    id: zenControls
    visible: Zen.active
    x: 4; y: 8; spacing: 4
    IconButton {
      width: 28; height: 28
      iconSource: "assets/close.svg"; iconWidth: 10; iconHeight: 10
      restingOpacity: 0.45
      onClicked: Zen.active = false
      Accessible.role: Accessible.Button
      Accessible.name: "Exit Zen mode"
      Accessible.onPressAction: Zen.active = false
    }
    Item {
      width: 28; height: zenPrivacy.height
      visible: zenPrivacy.presented
      Activity.PrivacyIndicator { id: zenPrivacy; anchors.horizontalCenter: parent.horizontalCenter }
    }
    ActionButton {
      width: 28; height: 28; text: "!"
      visible: Battery.State.low
      onClicked: root.togglePopup("battery")
      Accessible.role: Accessible.Button
      Accessible.name: "Low battery. Show details"
      Accessible.onPressAction: clicked()
    }
  }

  // Use the existing outer margin, outside the clock's clipped content and
  // click target. No extra row or sidebar space is reserved for privacy lights.
  Activity.PrivacyIndicator {
    visible: !Zen.active && presented
    x: mainStack.x + root.cardWidth - width - 4
    y: 1
    z: 5
  }

  Column {
    id: mainStack
    visible: !Zen.active
    x: Theme.sidebarOuterMargin
    y: Theme.sidebarOuterMargin
    spacing: Theme.sidebarCardGap

    Calendar.Clock {
      id: timeCard
      width: root.cardWidth
      collapseProgress: root.collapseProgress
      onClicked: { root.dismissPanels(); Notifications.State.togglePanel(root.screen.name); }
      onBatteryClicked: root.togglePopup("battery")
    }

    Minimap.Map {
      id: workspacesCard
      preloadIconColors: root.firstFramePresented
      screen: root.screen
      collapseProgress: root.collapseProgress
      maximumHeight: Math.max(64,
          bottomStack.y - Theme.sidebarCardGap - mainStack.y
          - timeCard.height - mediaCard.height - installsCard.height
          - (keyboardFeedback.visible ? keyboardFeedback.height + Theme.sidebarCardGap : 0)
          - Theme.sidebarCardGap * (1 + (mediaCard.visible ? 1 : 0) + (installsCard.visible ? 1 : 0)))
      onFocusRequested: index => NiriMsg.focusWorkspace(index)
      onWindowRequested: windowId => NiriMsg.focusWindow(windowId)
      onAddRequested: workspaceId => NiriMsg.openLauncher(workspaceId)
    }

    Media.Player {
      id: mediaCard
      collapseProgress: root.collapseProgress
    }

    Installs.SidebarCard {
      id: installsCard
      width: root.cardWidth
      collapseProgress: root.collapseProgress
    }
    KeyboardFeedback {
      id: keyboardFeedback
      screen: root.screen
      collapseProgress: root.collapseProgress
      expandedTopMargin: mainStack.y + keyboardFeedback.y
    }
  }

  TapHandler {
    enabled: root.panelOpen
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    gesturePolicy: TapHandler.DragThreshold
    property var panelAtPress: null
    onPressedChanged: if (pressed) panelAtPress = root.activePanel
    onTapped: eventPoint => {
      const panel = root.activePanel;
      if (!panel || panel !== panelAtPress) return;
      const x = eventPoint.position.x - panel.x;
      const y = eventPoint.position.y - panel.y;
      if (x < 0 || x > panel.width || y < 0 || y > panel.height)
        root.dismissPanels();
    }
  }

  DeferredPanel {
    id: wifiPanel
    preload: audioPanel.settled
    windowSource: Qt.resolvedUrl("wifi/Panel.qml")
    x: root.panelX
    z: 80
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Theme.sidebarOuterMargin
  }

  DeferredPanel {
    id: audioPanel
    preload: root.firstFramePresented
    windowSource: Qt.resolvedUrl("audio/Panel.qml")
    x: root.panelX
    z: 80
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Theme.sidebarOuterMargin
  }

  DeferredPanel {
    id: bluetoothPanel
    preload: wifiPanel.settled
    windowSource: Qt.resolvedUrl("bluetooth/Panel.qml")
    x: root.panelX
    z: 80
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Theme.sidebarOuterMargin
  }

  Column {
    id: bottomStack
    visible: !Zen.active
    onYChanged: cardBlur.changed()
    x: Theme.sidebarOuterMargin
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Theme.sidebarOuterMargin
    width: controls.width
    spacing: Theme.sidebarCardGap
    Screenshot.Preview {
      width: root.cardWidth
      outputName: root.screen.name
      collapsed: root.collapseProgress > 0.5
    }
    BrightnessFeedback {
      screen: root.screen
      collapseProgress: root.collapseProgress
      expandedBottomMargin: Theme.sidebarOuterMargin + controls.height + 8
    }
    BottomControls {
      id: controls
      collapseProgress: root.collapseProgress
      wifiOpen: wifiPanel.opened
      soundOpen: audioPanel.opened
      settingsOpen: Settings.State.opened && Settings.State.outputName === root.screen.name
      onWifiClicked: root.togglePanel("wifi")
      onSoundClicked: root.togglePanel("audio")
      onSettingsClicked: Settings.State.toggle(root.screen.name)
      onCollapseClicked: root.toggleRequested()
    }
  }
}
