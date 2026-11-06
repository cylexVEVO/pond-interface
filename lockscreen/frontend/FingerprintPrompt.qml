import QtQuick

Rectangle {
    id: root
    property bool scanning: false
    signal clicked

    implicitWidth: 352
    implicitHeight: 48
    radius: height / 2
    color: Qt.rgba(0.08, 0.06, 0.10, 0.72)
    border.width: 1
    border.color: Qt.alpha(theme.lavender, 0.16)

    Theme { id: theme }

    Image {
        x: 16
        anchors.verticalCenter: parent.verticalCenter
        width: 20; height: 24
        source: Qt.resolvedUrl("assets/fingerprint.svg")
        sourceSize: Qt.size(40, 48)
        opacity: 0.85
    }

    Text {
        x: 48
        anchors.verticalCenter: parent.verticalCenter
        width: action.x - x - 12
        text: root.scanning ? "Touch the fingerprint reader" : "Fingerprint unlock"
        font.family: theme.uiFont
        font.pixelSize: 13
        color: theme.text
        opacity: 0.85
        elide: Text.ElideRight
    }

    Rectangle {
        id: action
        objectName: "fingerprintAction"
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        width: 64; height: 32; radius: 16
        color: Qt.alpha(theme.lavender, hover.hovered || activeFocus ? 0.18 : 0.07)
        border.width: activeFocus ? 1 : 0
        border.color: Qt.alpha(theme.lavender, 0.6)
        activeFocusOnTab: enabled
        Accessible.role: Accessible.Button
        Accessible.name: root.scanning ? "Cancel fingerprint scan" : "Unlock with fingerprint"
        Accessible.onPressAction: if (enabled) root.clicked()
        Keys.onReturnPressed: if (enabled) root.clicked()
        Keys.onEnterPressed: if (enabled) root.clicked()
        Keys.onSpacePressed: if (enabled) root.clicked()
        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            anchors.centerIn: parent
            text: root.scanning ? "Cancel" : "Unlock"
            font.family: theme.uiFont
            font.pixelSize: 12
            color: theme.lavender
        }
        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.clicked() }
    }
}
