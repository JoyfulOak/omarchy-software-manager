import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as OmarchyTheme
import qs.Ui

Item {
  id: root
  property var shell: null
  property var bar: null
  property var anchorItem: null
  property var hostWidget: null
  property var manifest: null
  property bool opened: false
  property string searchText: ""
  property string sourceFilter: "All"
  property string status: ""
  property bool inventoryBusy: false
  property bool updatesBusy: false
  property bool actionBusy: false
  property string pendingAction: ""
  property var pendingApp: null
  readonly property string pluginId: "io.github.joyfuloak.omarchy-software-manager"
  readonly property string helperPath: decodeURIComponent(
    Qt.resolvedUrl("helpers/software_manager.py").toString().replace(/^file:\/\//, ""))
  readonly property color foreground: OmarchyTheme.Color.menu.text
  readonly property color secondary: Util.alpha(foreground, 0.62)
  readonly property color background: OmarchyTheme.Color.menu.background
  readonly property int totalUpdates: updatesModel.count
  readonly property int nativeUpdates: countUpdates("Arch") + countUpdates("AUR / foreign")
  readonly property int flatpakUpdates: countUpdates("Flatpak")

  function open(payloadJson) {
    opened = true
    refresh()
  }

  function close() {
    opened = false
    pendingAction = ""
    pendingApp = null
  }

  function dismiss() {
    close()
  }

  function refresh() {
    if (!inventoryProcess.running) {
      inventoryBusy = true
      inventoryProcess.running = true
    }
    if (!updatesProcess.running) {
      updatesBusy = true
      updatesProcess.running = true
    }
  }

  function setStatus(text) { status = text }

  function countUpdates(type) {
    var total = 0
    for (var i = 0; i < updatesModel.count; i++)
      if (updatesModel.get(i).type === type) total++
    return total
  }

  function appHasUpdate(type, appId, location) {
    for (var i = 0; i < updatesModel.count; i++) {
      var item = updatesModel.get(i)
      if (item.type === type && item.appId === appId
          && (type !== "Flatpak" || item.location === location)) return true
    }
    return false
  }

  function matches(app) {
    var query = searchText.trim().toLocaleLowerCase()
    if (sourceFilter !== "All" && app.type !== sourceFilter) return false
    if (query === "") return true
    return (app.name + " " + app.appId + " " + app.type + " " + app.source + " " + app.location)
      .toLocaleLowerCase().indexOf(query) >= 0
  }

  function requestUninstall(app) {
    if (actionBusy) return
    pendingApp = app
    pendingAction = "uninstall"
  }

  function requestUpdate(app) {
    if (actionBusy) return
    pendingApp = app
    pendingAction = app.type === "Flatpak" ? "flatpak-update" : "native-update"
  }

  function requestFlatpakUpdates() {
    if (actionBusy || flatpakUpdates === 0) return
    pendingApp = null
    pendingAction = "flatpak-update-all"
  }

  function requestNativeUpdates() {
    if (totalUpdates === 0) return
    pendingApp = null
    pendingAction = "native-update"
  }

  function cancelAction() {
    pendingAction = ""
    pendingApp = null
  }

  function confirmAction() {
    if (pendingAction === "native-update") {
      pendingAction = ""
      // Arch does not support safe partial upgrades. Use the user's configured
      // terminal so yay can show its transaction summary and ask before changes.
      Quickshell.execDetached(["omarchy", "launch", "tui", "/usr/bin/python3", helperPath, "upgrade-all"])
      setStatus("Opened a terminal for Arch/AUR and Flatpak updates.")
      pendingApp = null
      return
    }
    if (pendingAction === "flatpak-update" || pendingAction === "flatpak-update-all") {
      var location = pendingAction === "flatpak-update-all" ? "All installations" : pendingApp.location
      var appId = pendingAction === "flatpak-update-all" ? "all" : pendingApp.appId
      startAction(["flatpak-update", location, appId])
      return
    }
    if (pendingAction === "uninstall" && pendingApp) {
      startAction(["uninstall", pendingApp.type, pendingApp.appId, pendingApp.location])
    }
  }

  function startAction(args) {
    if (actionBusy) return
    actionBusy = true
    pendingAction = ""
    actionProcess.command = ["/usr/bin/python3", "-I", "-S", helperPath].concat(args)
    actionProcess.running = true
  }

  function loadApps(text) {
    try {
      var result = JSON.parse(text)
      appsModel.clear()
      for (var i = 0; i < result.apps.length; i++) {
        var app = result.apps[i]
        appsModel.append({
          appId: String(app.id), name: String(app.name), version: String(app.version),
          type: String(app.type), source: String(app.source), location: String(app.location)
        })
      }
      filterApps()
      if (result.errors && result.errors.length)
        setStatus(result.errors.join(" · "))
      else
        setStatus(appsModel.count + " installed apps and packages found.")
    } catch (error) {
      setStatus("Could not read the installed software list: " + String(error))
    }
  }

  function loadUpdates(text) {
    try {
      var result = JSON.parse(text)
      updatesModel.clear()
      for (var i = 0; i < result.updates.length; i++) {
        var item = result.updates[i]
        updatesModel.append({
          appId: String(item.id), type: String(item.type),
          current: String(item.current || ""), available: String(item.available || ""),
          location: String(item.location || "")
        })
      }
      if (result.errors && result.errors.length)
        setStatus(result.errors.join(" · "))
      else if (updatesModel.count === 0)
        setStatus("No updates reported by Arch, AUR, or Flatpak.")
      else
        setStatus(updatesModel.count + " available updates. Review the source and location on each row.")
    } catch (error) {
      setStatus("Could not read update status: " + String(error))
    }
  }

  ListModel { id: appsModel }
  ListModel { id: visibleAppsModel }
  ListModel { id: updatesModel }

  onSearchTextChanged: filterApps()
  onSourceFilterChanged: filterApps()

  function filterApps() {
    visibleAppsModel.clear()
    for (var i = 0; i < appsModel.count; i++) {
      var app = appsModel.get(i)
      if (matches(app)) visibleAppsModel.append({
        appId: app.appId, name: app.name, version: app.version,
        type: app.type, source: app.source, location: app.location
      })
    }
    if (appList) appList.positionViewAtBeginning()
  }

  Process {
    id: inventoryProcess
    command: ["/usr/bin/python3", "-I", "-S", root.helperPath, "inventory"]
    stdout: StdioCollector { id: inventoryOutput; waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(code) {
      root.inventoryBusy = false
      if (code === 0) root.loadApps(inventoryOutput.text)
      else root.setStatus("Software inventory failed (exit " + code + ").")
    }
  }

  Process {
    id: updatesProcess
    command: ["/usr/bin/python3", "-I", "-S", root.helperPath, "updates"]
    stdout: StdioCollector { id: updatesOutput; waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(code) {
      root.updatesBusy = false
      if (code === 0) root.loadUpdates(updatesOutput.text)
      else root.setStatus("Update check failed (exit " + code + ").")
    }
  }

  Process {
    id: actionProcess
    stdout: StdioCollector { id: actionOutput; waitForEnd: true }
    stderr: StdioCollector { id: actionError; waitForEnd: true }
    onExited: function(code) {
      root.actionBusy = false
      var result = null
      try { result = JSON.parse(actionOutput.text) } catch (error) {}
      if (code === 0 && result && result.ok) {
        root.setStatus(result.message || "Action completed.")
        root.refresh()
      } else {
        root.setStatus(result && result.message ? result.message : (actionError.text || "Action failed."))
      }
    }
  }

  KeyboardPanel {
    id: managerWindow
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    contentWidth: fittedContentWidth(Style.space(900))
    contentHeight: cappedContentHeight(Style.space(690))

    Rectangle {
      id: canvas
      anchors.fill: parent
      color: root.background

      Column {
        id: content
        anchors.fill: parent
        anchors.margins: Style.space(22)
        spacing: Style.space(12)

        Row {
          id: heading
          width: parent.width
          height: Style.space(42)
          spacing: Style.space(12)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "󰏖"
            textFormat: Text.PlainText
            color: OmarchyTheme.Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.title
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Software"
            textFormat: Text.PlainText
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
          }
          Item { width: 1; height: 1 }
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(150)
            height: Style.space(32)
            color: "transparent"
            border.color: Util.alpha(root.foreground, 0.35)
            border.width: 1
            radius: Style.cornerRadius
            Text {
              anchors.centerIn: parent
              text: "Check for updates"
              textFormat: Text.PlainText
              color: root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.refresh() }
          }
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(72)
            height: Style.space(32)
            color: "transparent"
            border.color: Util.alpha(root.foreground, 0.35)
            border.width: 1
            radius: Style.cornerRadius
            Text {
              anchors.centerIn: parent
              text: "Close"
              textFormat: Text.PlainText
              color: root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.dismiss() }
          }
        }

        Text {
          width: parent.width
          text: root.inventoryBusy ? "Reading installed apps…"
            : appsModel.count + " installed · " + (root.updatesBusy ? "checking updates…" : root.totalUpdates + " updates available")
          textFormat: Text.PlainText
          color: root.secondary
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        Row {
          id: actionBar
          width: parent.width
          height: Style.space(36)
          spacing: Style.space(8)

          Repeater {
            model: ["All", "Arch", "AUR / foreign", "Flatpak"]
            Rectangle {
              required property string modelData
              width: label.implicitWidth + Style.space(24)
              height: Style.space(32)
              anchors.verticalCenter: parent.verticalCenter
              radius: Style.cornerRadius
              color: root.sourceFilter === modelData ? Util.alpha(OmarchyTheme.Color.accent, 0.22) : "transparent"
              border.color: root.sourceFilter === modelData ? OmarchyTheme.Color.accent : Util.alpha(root.foreground, 0.3)
              border.width: 1
              Text {
                id: label
                anchors.centerIn: parent
                text: modelData
                textFormat: Text.PlainText
                color: root.sourceFilter === modelData ? OmarchyTheme.Color.accent : root.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.sourceFilter = modelData }
            }
          }

          Item { width: 1; height: 1 }

          Rectangle {
            visible: root.nativeUpdates > 0
            width: nativeUpdateLabel.implicitWidth + Style.space(24)
            height: Style.space(32)
            anchors.verticalCenter: parent.verticalCenter
            color: Util.alpha(OmarchyTheme.Color.accent, 0.18)
            radius: Style.cornerRadius
            Text {
              id: nativeUpdateLabel
              anchors.centerIn: parent
              text: "Update All (" + root.totalUpdates + ")"
              textFormat: Text.PlainText
              color: OmarchyTheme.Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.requestNativeUpdates() }
          }
          Rectangle {
            visible: root.flatpakUpdates > 0
            width: flatpakUpdateLabel.implicitWidth + Style.space(24)
            height: Style.space(32)
            anchors.verticalCenter: parent.verticalCenter
            color: Util.alpha(OmarchyTheme.Color.accent, 0.18)
            radius: Style.cornerRadius
            Text {
              id: flatpakUpdateLabel
              anchors.centerIn: parent
              text: "Update Flatpaks (" + root.flatpakUpdates + ")"
              textFormat: Text.PlainText
              color: OmarchyTheme.Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.requestFlatpakUpdates() }
          }
        }

        Rectangle {
          id: searchBox
          width: parent.width
          height: Style.space(38)
          color: Util.alpha(root.foreground, 0.04)
          border.color: Util.alpha(root.foreground, 0.24)
          border.width: 1
          radius: Style.cornerRadius
          TextInput {
            anchors.fill: parent
            anchors.margins: Style.space(10)
            verticalAlignment: TextInput.AlignVCenter
            color: root.foreground
            selectionColor: OmarchyTheme.Color.accent
            selectedTextColor: root.background
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            text: root.searchText
            onTextChanged: root.searchText = text
          }
          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            visible: root.searchText === ""
            text: "Search installed software by name, type, source, or location…"
            textFormat: Text.PlainText
            color: Util.alpha(root.foreground, 0.42)
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
        }

        ListView {
          id: appList
          width: parent.width
          height: Math.max(140, parent.height - heading.height - actionBar.height - searchBox.height - statusLine.implicitHeight - parent.spacing * 4)
          clip: true
          spacing: Style.space(6)
          model: visibleAppsModel
          boundsBehavior: Flickable.StopAtBounds
          delegate: Rectangle {
            required property string appId
            required property string name
            required property string version
            required property string type
            required property string source
            required property string location
            width: appList.width
            height: Style.space(76)
            color: Util.alpha(root.foreground, 0.035)
            border.color: Util.alpha(root.foreground, 0.12)
            border.width: 1
            radius: Style.cornerRadius

            Column {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(14)
              anchors.right: actions.left
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)
              Text {
                width: parent.width
                text: name
                textFormat: Text.PlainText
                color: root.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.subtitle
                font.bold: true
                elide: Text.ElideRight
              }
              Text {
                width: parent.width
                text: type + " · " + version + " · " + source + " · " + location
                textFormat: Text.PlainText
                color: root.secondary
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
              Text {
                width: parent.width
                text: appId
                textFormat: Text.PlainText
                color: Util.alpha(root.secondary, 0.82)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }

            Row {
              id: actions
              anchors.right: parent.right
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)

              Rectangle {
                visible: root.appHasUpdate(type, appId, location)
                width: Style.space(72)
                height: Style.space(30)
                color: Util.alpha(OmarchyTheme.Color.accent, 0.18)
                radius: Style.cornerRadius
                Text {
                  anchors.centerIn: parent
                  text: "Update"
                  textFormat: Text.PlainText
                  color: OmarchyTheme.Color.accent
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.requestUpdate({appId: appId, name: name, type: type, location: location})
                }
              }

              Rectangle {
                width: Style.space(82)
                height: Style.space(30)
                color: "transparent"
                border.color: Util.alpha(root.foreground, 0.32)
                border.width: 1
                radius: Style.cornerRadius
                Text {
                  anchors.centerIn: parent
                  text: "Uninstall"
                  textFormat: Text.PlainText
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.requestUninstall({appId: appId, name: name, type: type, location: location})
                }
              }
            }
          }
        }

        Text {
          id: statusLine
          width: parent.width
          text: root.actionBusy ? "Working…" : root.status
          textFormat: Text.PlainText
          wrapMode: Text.WrapAtWordBoundaryOrAnywhere
          color: root.actionBusy ? OmarchyTheme.Color.accent : root.secondary
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      Rectangle {
        visible: root.pendingAction !== ""
        anchors.fill: parent
        z: 20
        color: Util.alpha(root.background, 0.84)

        MouseArea { anchors.fill: parent; onClicked: {} }

        Rectangle {
          width: Math.min(parent.width - Style.space(48), Style.space(520))
          height: confirmColumn.implicitHeight + Style.space(40)
          anchors.centerIn: parent
          color: root.background
          border.color: root.pendingAction === "uninstall" ? OmarchyTheme.Color.urgent : OmarchyTheme.Color.accent
          border.width: 1
          radius: Style.cornerRadius

          Column {
            id: confirmColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(20)
            spacing: Style.space(14)

            Text {
              width: parent.width
              text: root.pendingAction === "uninstall" ? "Uninstall software?"
                : root.pendingAction === "native-update" ? "Update Arch/AUR software?"
                : "Update Flatpak software?"
              textFormat: Text.PlainText
              color: root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              width: parent.width
              text: root.pendingAction === "uninstall"
                ? "Remove “" + (root.pendingApp ? root.pendingApp.name : "") + "” (" + (root.pendingApp ? root.pendingApp.type : "") + ") from " + (root.pendingApp ? root.pendingApp.location : "") + "? User data is not explicitly deleted."
                : root.pendingAction === "native-update"
                  ? "Software will open a terminal to upgrade Arch/AUR packages and Flatpaks. Review each transaction before approving it."
                  : root.pendingAction === "flatpak-update-all"
                    ? "Update all Flatpak apps in their existing user and system installations? System updates may ask for authorization."
                    : "Update “" + (root.pendingApp ? root.pendingApp.name : "") + "” in its existing Flatpak installation?"
              textFormat: Text.PlainText
              color: root.secondary
              wrapMode: Text.WordWrap
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }
            Row {
              width: parent.width
              height: Style.space(36)
              spacing: Style.space(10)
              Item { width: parent.width - cancelButton.width - confirmButton.width - Style.space(10); height: 1 }
              Rectangle {
                id: cancelButton
                width: Style.space(92); height: Style.space(34)
                color: "transparent"
                border.color: Util.alpha(root.foreground, 0.34); border.width: 1
                radius: Style.cornerRadius
                Text { anchors.centerIn: parent; text: "Cancel"; textFormat: Text.PlainText; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.cancelAction() }
              }
              Rectangle {
                id: confirmButton
                width: Style.space(112); height: Style.space(34)
                color: root.pendingAction === "uninstall" ? Util.alpha(OmarchyTheme.Color.urgent, 0.2) : Util.alpha(OmarchyTheme.Color.accent, 0.2)
                border.color: root.pendingAction === "uninstall" ? OmarchyTheme.Color.urgent : OmarchyTheme.Color.accent
                border.width: 1; radius: Style.cornerRadius
                Text {
                  anchors.centerIn: parent
                  text: root.pendingAction === "uninstall" ? "Uninstall" : "Continue"
                  textFormat: Text.PlainText
                  color: root.pendingAction === "uninstall" ? OmarchyTheme.Color.urgent : OmarchyTheme.Color.accent
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.confirmAction() }
              }
            }
          }
        }
      }
    }
  }
}
