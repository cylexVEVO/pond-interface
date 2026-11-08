pragma ComponentBehavior: Bound
import QtQuick
import "." as Night
import ".." as Settings
import "../.." as Shell

Settings.Modal {
  id: root
  title: "Night display"
  contentHeight: fields.height + 30
  onBackRequested: Settings.State.back()
  Keys.onEscapePressed: Settings.State.back()
  Column {
    id: fields
    x: 30; width: root.width - 60; spacing: 8
    enabled: Night.State.ready
    Text {
      width: parent.width; height: implicitHeight + 12
      text: "Warmer colors for all displays in the evening."
      color: Shell.Theme.colors.text; opacity: 0.7; wrapMode: Text.Wrap
      font.family: Shell.Theme.fontFamily; font.pixelSize: 15
    }
    Settings.Field {
      width: parent.width; title: "Night display"; toggle: true
      checked: Night.State.settings.enabled
      onToggled: checked => Night.State.update({enabled: checked})
    }
    Text {
      width: parent.width; height: 35; verticalAlignment: Text.AlignVCenter
      text: "Intensity · " + Math.round(intensity.value * 100) + "%"
      color: Shell.Theme.colors.text; font.family: Shell.Theme.fontFamily; font.pixelSize: 15
    }
    Shell.Slider {
      id: intensity
      width: parent.width
      externalValue: Night.State.settings.intensity
      showInlineValue: false
      onMoved: Night.State.update({intensity: value})
      activeFocusOnTab: true
      Accessible.role: Accessible.Slider; Accessible.name: "Night display intensity"
      Keys.onLeftPressed: Night.State.update({intensity: Math.max(0, value - 0.05)})
      Keys.onRightPressed: Night.State.update({intensity: Math.min(1, value + 0.05)})
    }
    Text {
      width: parent.width; height: 35; verticalAlignment: Text.AlignVCenter
      text: "Schedule"; color: Shell.Theme.colors.text
      font.family: Shell.Theme.fontFamily; font.pixelSize: 15
    }
    Repeater {
      model: [{key: "manual", label: "Manual"}, {key: "custom", label: "Custom times"}, {key: "solar", label: "Sunset to sunrise"}]
      delegate: Settings.Field {
        required property var modelData
        width: fields.width; title: modelData.label
        value: Night.State.settings.schedule === modelData.key ? "Selected" : ""
        Accessible.role: Accessible.RadioButton
        Accessible.checked: Night.State.settings.schedule === modelData.key
        onClicked: Night.State.update({schedule: modelData.key})
      }
    }
    Input {
      width: parent.width; visible: Night.State.settings.schedule === "custom"
      title: "Start"; value: Night.State.settings.start; hint: "HH:MM"
      onEdited: value => Night.State.update({start: value})
    }
    Input {
      width: parent.width; visible: Night.State.settings.schedule === "custom"
      title: "End"; value: Night.State.settings.end; hint: "HH:MM"
      onEdited: value => Night.State.update({end: value})
    }
    Text {
      width: parent.width; visible: Night.State.settings.schedule === "custom"
      text: "24-hour local time. Schedules can run overnight."
      color: Shell.Theme.colors.text; opacity: 0.7; wrapMode: Text.Wrap
      font.family: Shell.Theme.fontFamily; font.pixelSize: 13
    }
    Input {
      width: parent.width; visible: Night.State.settings.schedule === "solar"
      title: "Latitude"; value: Night.State.settings.latitude; hint: "−90 to 90"
      onEdited: value => Night.State.update({latitude: value.trim()})
    }
    Input {
      width: parent.width; visible: Night.State.settings.schedule === "solar"
      title: "Longitude"; value: Night.State.settings.longitude; hint: "−180 to 180"
      onEdited: value => Night.State.update({longitude: value.trim()})
    }
    Text {
      width: parent.width; visible: Night.State.settings.schedule === "solar"
      text: "Enter your location in decimal degrees (south and west are negative). Stored on this device; sunrise and sunset are calculated locally."
      color: Shell.Theme.colors.text; opacity: 0.7; wrapMode: Text.Wrap
      font.family: Shell.Theme.fontFamily; font.pixelSize: 13
    }
    Text {
      width: parent.width; visible: !!Night.State.error
      text: Night.State.error; color: "#ffb4ab"; wrapMode: Text.Wrap
      font.family: Shell.Theme.fontFamily; font.pixelSize: 13
    }
  }
}
