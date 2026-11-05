import QtQuick

// Compile off-thread and incubate between frames, then retain the window.
// An early user request finishes an in-flight preload synchronously.
Loader {
  id: root
  required property bool requested
  required property bool preload
  required property url windowSource
  required property var initialProperties
  property bool initialized: false
  readonly property bool settled: status === Loader.Ready || status === Loader.Error
  asynchronous: !requested

  function ensureLoaded() {
    if (initialized && (requested || preload) && source.toString() === "")
      setSource(windowSource, initialProperties);
  }

  onRequestedChanged: ensureLoaded()
  onPreloadChanged: ensureLoaded()
  Component.onCompleted: {
    initialized = true;
    ensureLoaded();
  }
}
