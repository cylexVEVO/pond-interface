//@ pragma Env QSG_RENDER_LOOP = threaded
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import "authentication" as Authentication
import "battery" as Battery
import "settings" as Settings
import "settings/appearance" as Appearance
import "settings/system" as System
import "notifications" as Notifications
import "updates" as Updates
// Keep the wallpaper API and its implementation from the same checkout.
// An independently installed QML module can lag behind a shell update.
import "../wallpaper/desktop" as Wallpaper
import Pond.System

ShellRoot {
  id: root
  property bool expanded: true

  // Register the tray host even before its settings UI is opened.
  readonly property var trayItems: SystemTray.items
  readonly property string updateStatus: Updates.State.status

  Shortcuts {}
  // Load the optional Polkit module without making it a shell dependency.
  readonly property bool authenticationReady: Authentication.State.registered

  Logind {
    id: logind
    sleepInhibited: true
    onPreparingForSleepChanged: {
      if (preparingForSleep)
        sleepLock.running = true;
      else
        sleepInhibited = true;
    }
    onLockRequested: Quickshell.execDetached(["python3", Quickshell.shellDir + "/settings/session.py", "lock"])
  }

  Variants {
    readonly property var commands: ({
      lock: ["python3", Quickshell.shellDir + "/settings/session.py", "lock"],
      display: ["niri", "msg", "action", "power-off-monitors"],
      sleep: ["python3", Quickshell.shellDir + "/settings/session.py", "suspend"]
    })
    model: Object.keys(commands).filter(key => System.Idle.current[key] > 0)
        .map(key => ({timeout: System.Idle.current[key], command: commands[key]}))
    delegate: IdleMonitor {
      required property var modelData
      timeout: modelData.timeout
      onIsIdleChanged: if (isIdle) Quickshell.execDetached(modelData.command)
    }
  }

  Process {
    id: sleepLock
    command: ["sh", "-c", "python3 \"$0\" lock; for _ in $(seq 40); do qs -p \"$1\" ipc call lockscreen isSecure 2>/dev/null | grep -qx true && exit; qs -p /usr/share/pond-interface/lockscreen ipc call lockscreen isSecure 2>/dev/null | grep -qx true && exit; sleep 0.1; done", Quickshell.shellDir + "/settings/session.py", Quickshell.shellDir + "/../lockscreen"]
    onExited: if (logind.preparingForSleep) logind.sleepInhibited = false
  }

  FileView {
    path: Quickshell.screens.length
        ? (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/pond-interface/manual-shown"
        : ""
    printErrors: false
    onLoadFailed: error => {
      if (error !== FileViewError.FileNotFound) return;
      Settings.State.open("", "manual");
      Qt.callLater(() => setText("shown\n"));
    }
  }

  IpcHandler {
    target: "session"
    function lock() {
      Quickshell.execDetached(["python3", Quickshell.shellDir + "/settings/session.py", "lock"]);
    }
  }

  IpcHandler {
    target: "sidebar"
    function toggle() { root.expanded = !root.expanded; }
  }

  IpcHandler {
    target: "notifications"
    function toggle() {
      Notifications.State.togglePanel(Settings.State.focusedOutputName());
    }
  }

  IpcHandler {
    target: "manual"
    function open() { Settings.State.open("", "manual"); }
  }

  IpcHandler {
    target: "shortcuts"
    function open() { Settings.State.open("", "shortcuts"); }
  }

  IpcHandler {
    target: "settings"
    function toggle() { Settings.State.toggle(); }
    function open(page: string) {
      if (page && Settings.State.pages.indexOf(page) < 0) return;
      Settings.State.open("", page);
    }
    function close() { Settings.State.close(); }
  }

  Variants {
    model: Quickshell.screens
    delegate: Scope {
      id: output
      required property var modelData
      Wallpaper.Window {
        screen: modelData
        configured: Appearance.State.wallpaperReady
        previewSource: Appearance.State.wallpaperPreviewUrl
        custom: Appearance.State.wallpaperMode === "custom"
        dimmed: Theme.translucent
        imageSource: Appearance.State.wallpaperUrl
      }
      Sidebar {
        id: sidebar
        screen: modelData
        expanded: root.expanded
        onToggleRequested: root.expanded = !root.expanded
      }
      Notifications.ToastWindow { id: toast; bar: sidebar }
      DeferredWindow {
        id: notificationCenter
        preload: settingsWindow.settled
        requested: Notifications.State.panelOpen
            && Notifications.State.panelOutputName === output.modelData.name
        windowSource: Qt.resolvedUrl("notifications/CenterWindow.qml")
        initialProperties: ({bar: sidebar})
      }
      DeferredWindow {
        preload: notificationCenter.settled
        requested: sidebar.popup === "battery"
        windowSource: Qt.resolvedUrl("battery/Window.qml")
        initialProperties: ({bar: sidebar})
      }
      Battery.Notification { bar: sidebar; above: toast }
      PanelDismissWindow { bar: sidebar }
      DeferredWindow {
        id: settingsWindow
        preload: sidebar.panelsReady
        requested: Settings.State.opened && Settings.State.outputName === output.modelData.name
        windowSource: Qt.resolvedUrl("settings/Window.qml")
        initialProperties: ({menuScreen: Qt.binding(() => output.modelData)})
      }
    }
  }
}
