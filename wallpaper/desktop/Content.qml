import QtQuick
import Pond.Daylight

Rectangle {
  id: root
  property bool configured: true
  property bool custom: false
  property bool dimmed: false
  property url imageSource: ""
  property url previewSource: ""
  property date now: new Date()
  property bool live: true
  readonly property bool settled: configured && (custom ? image.settled
      : skyLoader.status === Loader.Ready || skyLoader.status === Loader.Error)
  color: "#0b101c"
  layer.enabled: root.dimmed
  layer.format: ShaderEffectSource.RGBA16F
  // Dither the scrim over custom wallpapers; the sky already includes noise.
  layer.effect: root.custom ? dither : null

  Component {
    id: dither
    ShaderEffect { fragmentShader: Qt.resolvedUrl("dither.frag.qsb") }
  }

  // Static wallpaper startup should never initialize the daylight shader.
  Loader {
    id: skyLoader
    anchors.fill: parent
    active: root.configured && !root.custom
    sourceComponent: Sky { live: false; now: root.now }
  }
  Timer {
    interval: 30000
    repeat: true
    running: root.configured && !root.custom && root.live && root.visible
    onRunningChanged: if (running) root.now = new Date()
    onTriggered: root.now = new Date()
  }
  ProgressiveImage {
    id: image
    anchors.fill: parent
    source: root.configured && root.custom ? root.imageSource : ""
    previewSource: root.configured && root.custom ? root.previewSource : ""
  }
  Rectangle {
    visible: root.dimmed
    width: parent.width * 788 / 1728
    height: parent.height
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.4) }
      GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0) }
    }
  }
}
