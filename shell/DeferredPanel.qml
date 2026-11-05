import QtQuick

// A stable sidebar handle while its panel compiles and incubates after startup.
// Keep the loader visible: a hidden parent would suppress item.visible and
// prevent the host from seeing the panel's opening/closing animation.
DeferredWindow {
  id: root
  requested: false
  initialProperties: ({})
  readonly property bool opened: item ? item.opened : false
  readonly property bool presented: item ? item.visible : false
  readonly property var blurRegion: item ? item.blurRegion : null
  onXChanged: if (blurRegion) blurRegion.changed()
  onYChanged: if (blurRegion) blurRegion.changed()

  function open() {
    requested = true;
    if (item) item.open();
    requested = false;
  }

  function closeAll() {
    if (item) item.closeAll();
  }
}
