import QtQuick
import QtQuick.Window

Item {
  id: root
  property url source: ""
  property url previewSource: ""
  property real pixelRatio: Window.window?.devicePixelRatio ?? 1
  readonly property bool sized: width > 0 && height > 0
  property url detailSource: ""
  readonly property bool ready: detail.status === Image.Ready || preview.status === Image.Ready

  readonly property bool settled: ready || detail.status === Image.Error

  function updateDetail() {
    if (!sized || source.toString() === "") { detailSource = ""; return; }
    // A newly generated custom preview must not cancel an existing decode.
    if (detailSource.toString() === source.toString()) return;
    if (previewSource.toString() === "" || preview.status === Image.Ready || preview.status === Image.Error)
      detailSource = source;
  }
  onSourceChanged: { detailSource = ""; Qt.callLater(updateDetail); }
  onPreviewSourceChanged: Qt.callLater(updateDetail)
  onSizedChanged: Qt.callLater(updateDetail)
  Component.onCompleted: Qt.callLater(updateDetail)

  Image {
    id: preview
    objectName: "wallpaperPreview"
    anchors.fill: parent
    source: root.sized ? root.previewSource : ""
    fillMode: Image.PreserveAspectCrop
    autoTransform: true
    // Generated local proxies are bounded to 960px. Decode these directly so
    // the first background cannot sit behind app icons in Qt's async queue.
    asynchronous: !root.previewSource.toString().startsWith("file:")
    visible: detail.status !== Image.Ready
    onStatusChanged: Qt.callLater(root.updateDetail)
  }
  Image {
    id: detail
    objectName: "wallpaperImage"
    anchors.fill: parent
    // Decode the tiny preview first; both images share Qt's image-loading pool.
    // Zero sourceSize means full native resolution, so wait for screen geometry.
    source: root.sized ? root.detailSource : ""
    sourceSize: Qt.size(Math.max(1, Math.ceil(width * root.pixelRatio)), Math.max(1, Math.ceil(height * root.pixelRatio)))
    fillMode: Image.PreserveAspectCrop
    autoTransform: true
    asynchronous: true
    visible: status === Image.Ready
  }
}
