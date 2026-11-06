import QtQuick
import "." as System
import ".." as Settings
import "../display" as Display
import "../.." as Shell
import "../../activity" as Activity

Settings.Modal {
  id: root
  objectName: "systemPanel"
  title: "System"; bodyTop: 92
  contentHeight: fields.height + 30
  onBackRequested: Settings.State.back()
  Keys.onEscapePressed: Settings.State.back()
  Column {
    id: fields
    x: 30; width: root.width - 60; spacing: 24
    Section {
      width: parent.width
      title: "Display"
      Settings.Field {
        objectName: "systemDisplay"
        width: parent.width; navigation: true
        title: "Display settings"; value: Display.State.summary
        onClicked: Settings.State.openPage("display")
      }
    }
    Section {
      width: parent.width
      title: "Input"
      Settings.Field {
        objectName: "systemMouse"
        width: parent.width; navigation: true
        title: "Mouse & trackpad"; value: Math.round(System.State.mouse.speed * 100) + "%"
        onClicked: Settings.State.openPage("mouse")
      }
      Settings.Field {
        objectName: "systemKeyboard"
        width: parent.width; navigation: true
        title: "Keyboard language"; value: System.State.languageNames.join(", ")
        onClicked: Settings.State.openPage("keyboard")
      }
      Settings.Field {
        objectName: "systemShortcuts"
        width: parent.width; navigation: true
        title: "Keyboard shortcuts"; value: ""
        onClicked: Settings.State.openPage("shortcuts")
      }
    }
    Section {
      width: parent.width
      title: "Security & sleep"
      Settings.Field {
        objectName: "systemLock"
        width: parent.width; navigation: true
        title: "Lock & sleep"; value: System.Idle.label(System.Idle.current.lock)
        onClicked: Settings.State.openPage("lock")
      }
      Settings.Field {
        width: parent.width; navigation: true
        title: "Fingerprints"; value: "Manage"
        onClicked: Settings.State.openPage("fingerprints")
      }
      Settings.Field {
        width: parent.width; toggle: true
        title: "Stay awake in Zen"; value: ""
        checked: System.Idle.zenKeepAwake
        onToggled: checked => System.Idle.setZenKeepAwake(checked)
        HoverHandler { id: zenHover }
        Activity.Hint {
          hovered: zenHover.hovered
          text: "Pauses automatic lock, display off and sleep during Zen. Manual lock and sleep still work."
        }
      }
      AuthenticationBanner { width: parent.width }
    }
    Section {
      width: parent.width
      title: "Region"
      Settings.Field {
        objectName: "systemTimezone"
        width: parent.width; navigation: true
        title: "Timezone"; value: System.State.timezoneLabel
        onClicked: Settings.State.openPage("timezone")
      }
    }
    Text {
      width: parent.width
      visible: !!Activity.State.audioError && !Activity.State.audioError.startsWith("Checking")
      text: "Recording detection unavailable"
      color: Qt.alpha(Shell.Theme.colors.text, 0.6)
      font.family: Shell.Theme.fontFamily; font.pixelSize: 12
      HoverHandler { id: detectionHover }
      Activity.Hint { hovered: detectionHover.hovered; text: Activity.State.audioError }
    }
    Text {
      width: parent.width
      visible: !!Activity.State.sleepError && !Activity.State.sleepError.startsWith("Checking")
      text: "Sleep blocker detection unavailable"
      color: Qt.alpha(Shell.Theme.colors.text, 0.6)
      font.family: Shell.Theme.fontFamily; font.pixelSize: 12
      HoverHandler { id: sleepDetectionHover }
      Activity.Hint { hovered: sleepDetectionHover.hovered; text: Activity.State.sleepError }
    }
    Text {
      width: parent.width; visible: !!System.State.error
      text: System.State.error; color: "#ffb4ab"; wrapMode: Text.Wrap
      font.family: Shell.Theme.fontFamily; font.pixelSize: 13
    }
  }

  component Section: Column {
    id: section
    required property string title
    default property alias fields: rows.data
    spacing: 10

    Text {
      width: parent.width
      text: section.title
      color: Qt.alpha(Shell.Theme.colors.text, 0.7)
      font.family: Shell.Theme.fontFamily
      font.pixelSize: 13
      font.weight: Font.Medium
      Accessible.role: Accessible.Heading
      Accessible.name: text
    }
    Column {
      id: rows
      width: parent.width
      spacing: 8
    }
  }
}
