import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as OmarchyTheme
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.joyfuloak.omarchy-software-manager"

  property bool popupOpen: false
  property int updateCount: 0
  property string summary: "Open Software to inspect installed apps and updates."
  readonly property bool opened: popupOpen
  readonly property string helperPath: decodeURIComponent(
    Qt.resolvedUrl("helpers/software_manager.py").toString().replace(/^file:\/\//, ""))

  function openManager() {
    popupOpen = false
    if (bar && bar.shell && typeof bar.shell.summon === "function")
      bar.shell.summon(moduleName, "{}")
  }

  function open() {
    popupOpen = true
    refreshSummary()
  }

  function close() { popupOpen = false }

  function togglePanel() {
    if (popupOpen) close()
    else open()
  }

  function refreshSummary() {
    if (!updatesProcess.running) updatesProcess.running = true
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  IpcHandler {
    target: "io.github.joyfuloak.omarchy-software-manager"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function refresh(): void { root.refreshSummary() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰏖"
    tooltipText: root.updateCount > 0
      ? "Software · " + root.updateCount + " updates available" : "Software"
    active: root.popupOpen
    useActiveColor: true
    activeColor: OmarchyTheme.Color.accent
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.MiddleButton) root.refreshSummary()
      else root.togglePanel()
    }
  }

  PopupCard {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(360))
    contentHeight: popup.fittedContentHeight(contents.implicitHeight)

    Column {
      id: contents
      anchors.fill: parent
      spacing: Style.space(12)

      Text {
        text: "Software"
        textFormat: Text.PlainText
        color: root.bar ? root.bar.foreground : OmarchyTheme.Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.title
        font.bold: true
      }

      Text {
        width: parent.width
        text: root.summary
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        color: root.bar ? Util.alpha(root.bar.foreground, 0.72) : OmarchyTheme.Color.muted
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
      }

      Rectangle {
        width: parent.width
        height: Style.space(36)
        color: OmarchyTheme.Color.accent
        radius: Style.cornerRadius

        Text {
          anchors.centerIn: parent
          text: "Open Software Manager"
          textFormat: Text.PlainText
          color: OmarchyTheme.Color.background
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.openManager()
        }
      }
    }
  }

  Process {
    id: updatesProcess
    command: ["/usr/bin/python3", "-I", "-S", root.helperPath, "updates"]
    stdout: StdioCollector { id: updatesOutput; waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) {
        root.summary = "Update check failed. Open Software for details."
        return
      }
      try {
        const result = JSON.parse(updatesOutput.text)
        root.updateCount = result.updates.length
        root.summary = root.updateCount === 0
          ? "Your package sources report no available updates."
          : root.updateCount + " update" + (root.updateCount === 1 ? "" : "s") + " available."
      } catch (error) {
        root.summary = "Could not read update status. Open Software for details."
      }
    }
  }
}
