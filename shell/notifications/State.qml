pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import ".." as Shell

Singleton {
  id: root
  property var historyNotifications: []
  readonly property int historyLimit: 100
  property var activeNotifications: []
  readonly property var recentApps: _recentApps(historyNotifications)
  property string transientId: ""
  property string transientOutputName: ""
  readonly property var currentTransient: _findById(activeNotifications, transientId)
  readonly property bool transientVisible: transientId !== "" && currentTransient !== null && !panelOpen && !Shell.Zen.active
  property bool panelOpen: false
  property string panelOutputName: ""
  readonly property int notificationCount: historyNotifications.length
  property var live: ({})
  property bool historyWritable: false
  property bool historyLoading: true
  property bool historyDirty: false
  property bool historyCleared: false
  property var historyRemoved: ({})

  SystemClock {
    id: clock
    precision: SystemClock.Seconds
    enabled: root.transientVisible
  }

  FileView {
    id: history
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
        + "/pond-interface/notifications.json"
    atomicWrites: true
    printErrors: false
    onLoaded: if (root.historyLoading && !recover.running) root.restoreHistory(text())
    onLoadFailed: error => {
      if (!root.historyLoading) return;
      if (error === FileViewError.FileNotFound) root.finishHistoryLoad([]);
      else {
        root.historyLoading = false;
        console.warn("Loading notification history:", error);
      }
    }
    onSaveFailed: error => console.warn("Saving notification history:", error)
  }

  function restoreHistory(text) {
    try {
      const saved = JSON.parse(text || "{}").notifications || [];
      if (!Array.isArray(saved)) throw new Error("Invalid notification history");
      finishHistoryLoad(saved);
    } catch (error) {
      // Preserve unreadable history before starting a fresh file.
      recover.command = ["mv", "--", history.path, history.path + ".unreadable-" + Date.now()];
      recover.running = true;
    }
  }

  function finishHistoryLoad(saved) {
    const dirty = historyDirty;
    // Notifications can arrive, be dismissed, or be cleared while disk I/O is
    // pending. Live state wins, and dismissed history must not reappear.
    const seen = new Set(historyNotifications.map(n => n.id));
    const restored = historyCleared ? [] : saved.filter(n => {
      if (!n || !n.id || seen.has(n.id) || historyRemoved[n.id]) return false;
      seen.add(n.id);
      return true;
    });
    historyNotifications = historyNotifications.concat(restored).slice(0, historyLimit);
    historyLoading = false;
    historyWritable = true;
    historyRemoved = ({});
    if (dirty) save.restart();
  }

  Process {
    id: recover
    onExited: code => {
      if (code === 0) {
        root.historyDirty = true;
        root.finishHistoryLoad([]);
      } else {
        root.historyLoading = false;
        console.warn("Could not preserve unreadable notification history:", history.path);
      }
    }
  }

  onHistoryNotificationsChanged: {
    if (historyWritable) save.restart();
  }
  Timer {
    id: save
    interval: 50
    onTriggered: history.setText(JSON.stringify({ notifications: root.historyNotifications }))
  }

  NotificationServer {
    keepOnReload: true
    persistenceSupported: true
    actionsSupported: true
    bodySupported: true
    bodyMarkupSupported: false
    imageSupported: false
    onNotification: notification => root.receive(notification)
  }

  function snapshot(n, id) {
    const saved = _findById(historyNotifications, id) || _findById(activeNotifications, id);
    return { id, summary: n.summary, body: n.body, appName: n.appName,
      appIcon: n.appIcon, desktopEntry: n.desktopEntry,
      timestamp: saved ? saved.timestamp : Date.now() };
  }

  function receive(notification) {
    notification.tracked = true;
    const id = Quickshell.processId + ":" + notification.id;
    if (!live[id]) live[id] = watcher.createObject(root, { notification, notificationId: id });
    live[id].refresh();
    if (!notification.lastGeneration && !panelOpen && !Shell.Zen.active) {
      transientOutputName = Shell.NiriMsg.focusedOutputName || Quickshell.screens[0]?.name || "";
      transientId = id;
    }
  }

  Component {
    id: watcher
    Scope {
      id: entry
      required property var notification
      required property string notificationId
      property bool closed: false

      function refresh() {
        if (closed) return;
        const data = root.snapshot(notification, notificationId);
        root.activeNotifications = [data, ...root.activeNotifications.filter(n => n.id !== notificationId)];
        if (!notification.transient) {
          if (root.historyLoading) root.historyDirty = true;
          const updated = [data, ...root.historyNotifications.filter(n => n.id !== notificationId)];
          root.historyNotifications = updated.slice(0, root.historyLimit);
          for (const removed of updated.slice(root.historyLimit)) root.remove(removed);
        }
        popupTimeout.restart();
      }
      function scheduleRefresh() { Qt.callLater(refresh); }
      Timer {
        id: popupTimeout
        interval: [3000, 8000, 15000][entry.notification.urgency] || 8000
        onTriggered: {
          if (entry.notification.transient) root.remove({ id: entry.notificationId });
          else if (root.transientId === entry.notificationId) root.transientId = "";
        }
      }
      Connections {
        target: entry.notification
        function onSummaryChanged() { entry.scheduleRefresh(); }
        function onBodyChanged() { entry.scheduleRefresh(); }
        function onAppIconChanged() { entry.scheduleRefresh(); }
        function onClosed(reason) {
          entry.closed = true;
          delete root.live[entry.notificationId];
          root.remove({ id: entry.notificationId });
          entry.destroy();
        }
      }
    }
  }

  function _findById(items, id) {
    if (!id)
      return null;
    for (const item of items) {
      if (item.id === id)
        return item;
    }
    return null;
  }

  function _identity(notification) {
    const raw = notification.desktopEntry || notification.appName || "unknown";
    return raw.toLowerCase().replace(/[^a-z0-9]+/g, "");
  }

  function _recentApps(items) {
    const seen = ({});
    const result = [];
    for (const item of items) {
      const key = _identity(item);
      if (seen[key])
        continue;
      seen[key] = true;
      result.push({
                    identity: key,
                    name: item.appName,
                    notification: item
                  });
      if (result.length >= 5)
        break;
    }
    return result;
  }

  function iconSource(notification) {
    const rawIcon = String(notification.appIcon || "");
    if (rawIcon.startsWith("file:") || rawIcon.startsWith("image:")
        || rawIcon.startsWith("qrc:"))
      return rawIcon;
    if (rawIcon.startsWith("/"))
      return "file://" + rawIcon;
    if (rawIcon !== "")
      return Quickshell.iconPath(rawIcon, "application-x-executable");

    const candidates = [notification.desktopEntry, notification.appName];
    for (const candidate of candidates) {
      if (!candidate)
        continue;
      try {
        const lower = String(candidate).toLowerCase();
        const entry = DesktopEntries.byId(candidate)
            || DesktopEntries.byId(lower)
            || DesktopEntries.heuristicLookup(candidate)
            || DesktopEntries.heuristicLookup(lower);
        if (entry && entry.icon)
          return Quickshell.iconPath(entry.icon, "application-x-executable");
      } catch (error) {}
    }

    const fallback = String(notification.appName || "application-x-executable")
        .toLowerCase().replace(/\s+/g, "-");
    return Quickshell.iconPath(fallback, "application-x-executable");
  }

  function title(notification) {
    if (!notification)
      return "";
    return notification.summary ? String(notification.summary)
                                : String(notification.appName || "");
  }

  function message(notification) {
    if (!notification)
      return "";
    return notification.body ? String(notification.body)
                             : String(notification.summary || "");
  }

  function relativeTimeLabel(timestamp) {
    const minutes = Math.max(0, Math.floor((clock.date.getTime() - timestamp) / 60000));
    if (minutes < 1) return "Now";
    if (minutes < 60) return minutes + "m";
    if (minutes < 1440) return Math.floor(minutes / 60) + "h";
    return Math.floor(minutes / 1440) + "d";
  }

  function timeLabel(timestamp) {
    const date = new Date(Number(timestamp));
    let hours = date.getHours();
    const suffix = hours >= 12 ? "PM" : "AM";
    hours = hours % 12;
    if (hours === 0)
      hours = 12;
    const minutes = String(date.getMinutes()).padStart(2, "0");
    return hours + ":" + minutes + " " + suffix;
  }

  function togglePanel(outputName) {
    if (Shell.Zen.active) return;
    if (panelOpen && panelOutputName === outputName) { closePanel(); return; }
    transientId = "";
    panelOutputName = outputName;
    panelOpen = true;
  }

  function closePanel() { panelOpen = false; }

  function remove(notification) {
    if (!notification || !notification.id) return;
    const id = notification.id;
    if (historyLoading) {
      historyDirty = true;
      historyRemoved[id] = true;
    }
    if (transientId === id) transientId = "";
    historyNotifications = historyNotifications.filter(n => n.id !== id);
    activeNotifications = activeNotifications.filter(n => n.id !== id);
    if (live[id]) live[id].notification.dismiss();
  }

  function activate(notification) {
    if (!notification || !notification.id) return;
    const n = live[notification.id]?.notification;
    const action = n?.actions.find(a => a.identifier === "default");
    if (action) action.invoke();
    else Shell.NiriMsg.focusApp(notification.appName, notification.desktopEntry);
    remove(notification);
    transientId = "";
    closePanel();
  }

  function clearAll() {
    if (historyLoading) {
      historyDirty = true;
      historyCleared = true;
    }
    for (const id of Object.keys(live))
      live[id]?.notification.dismiss();
    historyNotifications = [];
    activeNotifications = [];
    transientId = "";
  }
}
