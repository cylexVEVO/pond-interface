pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import "." as Session
import "../frontend" as Frontend

Item {
    id: root

    required property var powerBackend
    property string displayName: ""
    property bool wifiConnected: false
    property list<string> presentationOutputs: []
    readonly property bool secure: lockSession.secure
    readonly property bool configuredOutputPresent: Quickshell.screens.some(screen => presentationOutputs.includes(screen.name))

    signal finished

    function showsPresentation(screen) {
        return !configuredOutputPresent || presentationOutputs.includes(screen.name);
    }

    Authentication { id: auth }
    Session.Transition {
        id: handoff
        controller: ui.controller
        exitTransition: ui.exitTransition
        released: flow.phase === "exiting"
        displayName: root.displayName
        wifiConnected: root.wifiConnected
        presentationOutputs: Quickshell.screens.filter(screen => root.showsPresentation(screen)).map(screen => screen.name)
    }
    Frontend.Controller {
        id: ui
        powerBackend: root.powerBackend
        inputBlocked: !auth.pamReady
    }
    SessionController {
        id: flow
        frontend: ui
        authentication: auth
        transition: handoff
        onReleaseRequested: lockSession.locked = false
        onFinished: root.finished()
    }

    WlSessionLock {
        id: lockSession
        locked: true

        WlSessionLockSurface {
            id: surface
            readonly property bool showPresentation: root.showsPresentation(screen)
            color: showPresentation ? "#1a1409" : "black"

            Button {
                z: 10
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 32
                visible: surface.showPresentation
                text: auth.authenticationPending && auth.fingerprintMode ? "Cancel fingerprint scan" : "Unlock with fingerprint"
                enabled: flow.phase === "editing" || (flow.phase === "authenticating" && auth.fingerprintMode)
                onClicked: {
                    if (auth.authenticationPending) { auth.reset(); flow.reject(); }
                    else flow.attemptFingerprint();
                }
            }

            Frontend.Screen {
                anchors.fill: parent
                controller: ui
                showPresentation: surface.showPresentation
                displayName: root.displayName
                wifiConnected: root.wifiConnected
            }
        }
    }
}
