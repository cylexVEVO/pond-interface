pragma ComponentBehavior: Bound

import QtQuick
import "." as Settings
import ".." as Shell
import "../authentication" as Authentication
import "appearance" as Appearance
import "night" as Night
import "display" as Display
import "information" as Information
import "manual" as Manual
import "system" as System
import "shortcuts" as Shortcuts
import "../battery" as Battery
import "../updates" as Updates
import Quickshell
import Quickshell.Wayland

PanelWindow {
  id: root

  required property var menuScreen

  property bool presented: false
  property int revealStep: -1
  property var revealRanks: []
  readonly property int cardCount: primaryButtons.length + sessionButtons.length
  property string displayedPage: Settings.State.page || "appearance"
  property real pageOpacity: 1
  property real pageOffset: 0
  property real pageScale: 1
  property int slideDirection: 1

  function resetPageMotion() {
    pageTransition.stop();
    pageOpacity = 1;
    pageOffset = 0;
    pageScale = 1;
  }

  function navigatePage() {
    const next = Settings.State.page;
    if (!next) { resetPageMotion(); return; }
    if (!targetOpen || !modal.item || modal.opacity < 0.01) {
      resetPageMotion();
      displayedPage = next;
      return;
    }
    if (next === displayedPage && !pageTransition.running) return;
    pageTransition.stop();
    slideDirection = Settings.State.navigationDirection;
    pageTransition.start();
  }

  readonly property bool targetOpen: Settings.State.opened
      && Settings.State.outputName === (menuScreen ? menuScreen.name : "")
  readonly property bool cardsOpen: targetOpen && Settings.State.page === ""
  readonly property bool modalOpen: targetOpen && Settings.State.page !== ""

  readonly property var primaryButtons: [
    {
      slot: 0, x: 0, y: 0, name: "Appearance", page: "appearance",
      source: Qt.resolvedUrl("../assets/settings/appearance.svg"),
      boxWidth: 48, boxHeight: 48, iconWidth: 48, iconHeight: 48
    },
    {
      slot: 1, x: 274, y: 0, name: "Bluetooth", page: "",
      source: Qt.resolvedUrl("../assets/settings/bluetooth.svg"),
      boxWidth: 30, boxHeight: 48, iconWidth: 30, iconHeight: 48
    },
    {
      slot: 2, x: 0, y: 274, name: "System", page: "system",
      source: Qt.resolvedUrl("../assets/settings/system.svg"),
      boxWidth: 48, boxHeight: 48, iconWidth: 42, iconHeight: 36
    },
    {
      slot: 3, x: 274, y: 274, name: "Information", page: "information",
      source: Qt.resolvedUrl("../assets/settings/information.svg"),
      boxWidth: 48, boxHeight: 48, iconWidth: 48, iconHeight: 48
    }
  ]

  readonly property var sessionButtons: [
    {
      slot: 4, y: 0, action: "lock", name: "Lock screen",
      source: Qt.resolvedUrl("../assets/lock.svg"),
      iconWidth: 32, iconHeight: 32,
      hover: "#FFE51D", control: "#632B0F", labelWidth: 170,
      dot: false
    },
    {
      slot: 5, y: 137, action: "suspend", name: "Sleep",
      source: Qt.resolvedUrl("../assets/settings/sleep.svg"),
      iconWidth: 32, iconHeight: 32,
      hover: "#E99FFF", control: "#681D4F", labelWidth: 74,
      dot: false
    },
    {
      slot: 6, y: 274, action: "reboot", name: "Restart",
      updatingName: "Restart after update", pendingName: "Restarting after update",
      source: Qt.resolvedUrl("../assets/settings/restart.svg"),
      iconWidth: 32, iconHeight: 32,
      hover: "#CEF058", control: "#1B322D", labelWidth: 99,
      dot: false
    },
    {
      slot: 7, y: 411, action: "shutdown", name: "Power off",
      updatingName: "Shutdown after update", pendingName: "Shutting down after update",
      source: Qt.resolvedUrl("../assets/settings/power.svg"),
      iconWidth: 32, iconHeight: 32,
      hover: "#FE6146", control: "#632B0F", labelWidth: 127,
      dot: true
    }
  ]

  screen: menuScreen
  visible: presented && !Appearance.State.pickingWallpaper
  color: "transparent"
  BackgroundEffect.blurRegion: Shell.Theme.translucent ? cardBlur : null
  onWidthChanged: cardBlur.changed()
  onHeightChanged: cardBlur.changed()
  Region {
    id: cardBlur
    regions: Array.from(composition.children).concat(profileSelector, tray, modal.item)
        .filter(Boolean).map(item => item.blurRegion).filter(Boolean)
  }

  anchors {
    left: true
    right: true
    top: true
    bottom: true
  }

  // Authentication owns input until its request completes or is cancelled.
  WlrLayershell.layer: Authentication.State.promptActive ? WlrLayer.Top : WlrLayer.Overlay
  WlrLayershell.namespace: "pond-settings-"
      + (screen ? screen.name : "unknown")
  WlrLayershell.keyboardFocus: root.targetOpen && !Authentication.State.promptActive
      ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
  WlrLayershell.exclusionMode: ExclusionMode.Ignore

  mask: Region {
    x: 0
    y: 0
    width: root.presented ? root.width : 0
    height: root.presented ? root.height : 0
  }

  Connections {
    target: Authentication.State
    function onPromptActiveChanged() {
      if (!Authentication.State.promptActive && root.modalOpen && modal.item)
        Qt.callLater(() => { if (!Authentication.State.promptActive && root.modalOpen && modal.item) modal.item.forceActiveFocus(); });
    }
  }

  onTargetOpenChanged: {
    if (targetOpen)
      beginOpen();
    else
      beginClose();
  }
  onCardsOpenChanged: if (cardsOpen) beginOpen()
  Component.onCompleted: if (targetOpen) beginOpen()
  Connections {
    target: Settings.State
    function onPageChanged() {
      root.navigatePage();
    }
  }

  Rectangle {
    anchors.fill: parent
    color: Settings.Style.overlay
    opacity: root.targetOpen ? Settings.Style.overlayOpacity : 0

    Behavior on opacity {
      NumberAnimation {
        duration: Settings.Style.closeDuration
        easing.type: Easing.OutCubic
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    enabled: root.targetOpen && !Authentication.State.promptActive
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    onClicked: Settings.State.close()
  }

  Item {
    id: composition
    z: 2
    width: 675
    height: 538
    anchors.centerIn: parent
    clip: false
    enabled: root.cardsOpen && !Authentication.State.promptActive
    visible: opacity > 0
    opacity: root.cardsOpen ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Settings.Style.closeDuration; easing.type: Easing.OutCubic } }

    Repeater {
      model: root.primaryButtons

      delegate: CategoryButton {
        required property var modelData

        x: modelData.x
        y: modelData.y
        width: 264
        height: 264
        iconSource: modelData.source
        iconBoxWidth: modelData.boxWidth
        iconBoxHeight: modelData.boxHeight
        iconWidth: modelData.iconWidth
        iconHeight: modelData.iconHeight
        accessibleName: modelData.name
        onClicked: {
          if (modelData.page) Settings.State.openPage(modelData.page);
          else Settings.State.openBluetooth();
        }
        revealed: root.cardsOpen
            && root.revealStep >= root.revealRanks[modelData.slot]
      }
    }

    Repeater {
      model: root.sessionButtons

      delegate: SessionButton {
        required property var modelData
        readonly property bool afterUpdate: Updates.State.status === "updating" && !!modelData.updatingName

        x: 548
        y: modelData.y
        width: Settings.Style.sessionSize
        height: Settings.Style.sessionSize
        iconSource: modelData.source
        iconWidth: modelData.iconWidth
        iconHeight: modelData.iconHeight
        showStatusDot: modelData.dot
        highlighted: modelData.action === "reboot" && updateBadge.restartHovered
        hoverColor: modelData.hover
        hoverControlColor: modelData.control
        label: !afterUpdate ? modelData.name
            : Updates.State.pending === modelData.action ? modelData.pendingName : modelData.updatingName
        labelWidth: modelData.labelWidth
        accessibleName: modelData.name
        revealed: root.cardsOpen
            && root.revealStep >= root.revealRanks[modelData.slot]
        onClicked: afterUpdate ? Updates.State.after(modelData.action)
            : Settings.State.requestSessionAction(modelData.action)
      }
    }
  }

  Updates.Badge {
    id: updateBadge
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 15
    visible: root.cardsOpen && status !== ""
  }

  Battery.ProfileSelector {
    id: profileSelector
    z: 2
    anchors.right: parent.right
    anchors.rightMargin: 10
    anchors.verticalCenter: parent.verticalCenter
    enabled: root.cardsOpen && !Authentication.State.promptActive
    visible: opacity > 0
    opacity: root.cardsOpen ? 1 : 0
    Keys.onEscapePressed: Settings.State.close()
    Behavior on opacity {
      NumberAnimation { duration: Settings.Style.closeDuration; easing.type: Easing.OutCubic }
    }
  }

  Tray {
    id: tray
    z: 3
    anchors.fill: parent
    enabled: root.cardsOpen && !Authentication.State.promptActive
    visible: opacity > 0
    opacity: root.cardsOpen ? 1 : 0
    Behavior on opacity {
      NumberAnimation { duration: Settings.Style.closeDuration; easing.type: Easing.OutCubic }
    }
  }

  // Keep navigation, transitions, and outside-click dismissal in the host.
  Loader {
    id: modal
    z: 3
    anchors.centerIn: parent
    active: root.presented && (root.modalOpen || opacity > 0)
    sourceComponent: ({
      night: nightPage, wallpaper: wallpaperPage, information: informationPage, manual: manualPage, display: displayPage, arrange: arrangePage,
      system: systemPage, mouse: mousePage, lock: lockPage, keyboard: keyboardPage,
      shortcuts: shortcutsPage, shortcutEditor: shortcutEditorPage, timezone: timezonePage, fingerprints: fingerprintsPage
    })[root.displayedPage] || appearancePage
    enabled: root.modalOpen && !Authentication.State.promptActive && !pageTransition.running
    opacity: root.modalOpen ? root.pageOpacity : 0
    transform: [
      Translate { x: root.pageOffset },
      Scale { origin.x: modal.width / 2; origin.y: modal.height / 2; xScale: root.pageScale; yScale: root.pageScale }
    ]
    scale: root.modalOpen ? 1 : 0.96
    Behavior on opacity {
      enabled: root.displayedPage !== "appearance" && !pageTransition.running
      NumberAnimation { duration: Settings.Style.closeDuration; easing.type: Easing.OutCubic }
    }
    Behavior on scale { NumberAnimation { duration: Settings.Style.closeDuration; easing.type: Easing.OutCubic } }
    onLoaded: if (root.modalOpen && !Authentication.State.promptActive) item.forceActiveFocus()
    onXChanged: cardBlur.changed()
    onYChanged: cardBlur.changed()
    onScaleChanged: cardBlur.changed()
  }
  // Swap only once the old surface has faded; never keep two live settings
  // pages around (some pages own authentication or enrollment processes).
  SequentialAnimation {
    id: pageTransition
    ParallelAnimation {
      NumberAnimation { target: root; property: "pageOpacity"; to: 0; duration: 100; easing.type: Easing.InCubic }
      NumberAnimation { target: root; property: "pageOffset"; to: -14 * root.slideDirection; duration: 100; easing.type: Easing.InCubic }
      NumberAnimation { target: root; property: "pageScale"; to: 0.985; duration: 100; easing.type: Easing.InCubic }
    }
    ScriptAction {
      script: {
        root.displayedPage = Settings.State.page;
        root.pageOffset = 28 * root.slideDirection;
        root.pageScale = 0.985;
      }
    }
    ParallelAnimation {
      NumberAnimation { target: root; property: "pageOpacity"; to: 1; duration: 180; easing.type: Easing.OutCubic }
      NumberAnimation { target: root; property: "pageOffset"; to: 0; duration: 260; easing.type: Easing.OutQuint }
      NumberAnimation { target: root; property: "pageScale"; to: 1; duration: 260; easing.type: Easing.OutQuint }
    }
    onFinished: {
      if (root.modalOpen && !Authentication.State.promptActive && modal.item)
        modal.item.forceActiveFocus();
    }
  }
  onPageOffsetChanged: cardBlur.changed()
  onPageScaleChanged: cardBlur.changed()

  Component {
    id: displayPage
    Display.Panel {
      availableHeight: root.height - 80
      scale: Math.min(1, (root.width - 60) / implicitWidth)
    }
  }
  Component {
    id: arrangePage
    Display.Arrange {
      availableHeight: root.height - 80
      scale: Math.min(1, (root.width - 60) / implicitWidth)
    }
  }
  Component {
    id: nightPage
    Night.Panel {
      availableHeight: Math.max(200, root.height - 70)
      scale: Math.min(1, (root.width - 60) / implicitWidth)
    }
  }
  Component {
    id: appearancePage
    Appearance.Panel {
      availableHeight: Math.max(200, root.height - 70)
      scale: Math.min(1, (root.width - 60) / implicitWidth)
    }
  }
  Component {
    id: wallpaperPage
    Appearance.WallpaperPicker {
      availableHeight: Math.max(200, root.height - 70)
      scale: Math.min(1, (root.width - 60) / implicitWidth)
    }
  }
  Component {
    id: informationPage
    Information.Panel {
      availableHeight: Math.max(200, root.height - 70)
      scale: Math.min(1, (root.width - 60) / implicitWidth)
    }
  }
  Component {
    id: systemPage
    System.Panel {
      availableHeight: Math.max(200, root.height - 70)
      scale: Math.min(1, (root.width - 60) / implicitWidth)
    }
  }
  Component {
    id: mousePage
    System.Mouse {
      availableHeight: Math.max(200, root.height - 70)
      scale: Math.min(1, (root.width - 60) / implicitWidth)
    }
  }
  Component {
    id: lockPage
    System.Lock {
      availableHeight: Math.max(200, root.height - 70)
      scale: Math.min(1, (root.width - 60) / implicitWidth)
    }
  }
  Component {
    id: keyboardPage
    System.Picker {
      title: "Keyboard language"; placeholder: "Search languages"; multiple: true
      options: System.State.languages; selected: System.State.selectedLanguages
      onPicked: id => System.State.toggleLanguage(id)
      availableHeight: Math.max(200, root.height - 70)
      scale: Math.min(1, (root.width - 60) / implicitWidth)
    }
  }
  Component {
    id: shortcutsPage
    Shortcuts.Panel {
      availableHeight: Math.max(200, root.height - 70)
      scale: Math.min(1, (root.width - 60) / implicitWidth)
    }
  }
  Component {
    id: shortcutEditorPage
    Shortcuts.Editor {
      availableHeight: Math.max(200, root.height - 70)
      scale: Math.min(1, (root.width - 60) / implicitWidth)
    }
  }
  Component {
    id: timezonePage
    System.Picker {
      title: "Timezone"; placeholder: "Search timezone"
      options: System.State.timezones; selected: [System.State.timezone]
      onPicked: id => System.State.setTimezone(id)
      availableHeight: Math.max(200, root.height - 70)
      scale: Math.min(1, (root.width - 60) / implicitWidth)
    }
  }
  Component {
    id: manualPage
    Manual.Panel {
      availableHeight: Math.max(200, root.height - 70)
      scale: Math.min(1, (root.width - 60) / implicitWidth)
    }
  }
  Item {
    focus: root.cardsOpen
    Keys.onEscapePressed: Settings.State.close()
  }

  Timer {
    id: revealTimer
    interval: Settings.Style.staggerInterval
    repeat: true
    onTriggered: {
      if (root.revealStep >= root.cardCount - 1) {
        stop();
        return;
      }
      root.revealStep += 1;
    }
  }

  Timer {
    id: closeCleanup
    interval: Settings.Style.closeDuration
    onTriggered: {
      if (!root.targetOpen)
        root.presented = false;
    }
  }

  function beginOpen() {
    closeCleanup.stop();
    revealTimer.stop();
    revealRanks = shuffledRanks();
    revealStep = -1;
    presented = true;
    Qt.callLater(function() {
      if (!root.targetOpen)
        return;
      root.revealStep = 0;
      revealTimer.restart();
    });
  }

  function beginClose() {
    resetPageMotion();
    revealTimer.stop();
    revealStep = -1;
    if (presented)
      closeCleanup.restart();
  }

  function shuffledRanks() {
    const order = Array.from({length: root.cardCount}, (_, index) => index);
    for (let index = order.length - 1; index > 0; --index) {
      const other = Math.floor(Math.random() * (index + 1));
      const held = order[index];
      order[index] = order[other];
      order[other] = held;
    }
    return order;
  }
  Component {
    id: fingerprintsPage
    System.Fingerprints { availableHeight: root.height - 80 }
  }
}
