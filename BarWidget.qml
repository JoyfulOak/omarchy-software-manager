import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as OmarchyTheme
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.joyfuloak.omarchy-software-manager"
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened : false
  readonly property int updateCount: panelLoader.item ? panelLoader.item.totalUpdates : 0

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
    panelLoader.item.shell = root.bar ? root.bar.shell : null
  }
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (opened) close(); else open() }
  function refresh() { if (panelLoader.item) panelLoader.item.refresh() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Loader {
    id: panelLoader
    active: true
    source: "Panel.qml"
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }
  IpcHandler {
    target: "io.github.joyfuloak.omarchy-software-manager"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function refresh(): void { root.refresh() }
  }
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰏖"
    tooltipText: root.updateCount > 0 ? "Software · " + root.updateCount + " updates" : "Software"
    active: root.opened
    useActiveColor: true
    activeColor: OmarchyTheme.Color.accent
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }
  }
}
