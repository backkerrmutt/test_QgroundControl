import QtQuick
import QtQuick.Dialogs
import QGroundControl
import QGroundControl.Controls
import QGroundControl.ScreenTools

Item {
    id: root
    property var axisRouter: null

    signal importedOk()
    signal exportOk()
    signal errorOccured(string msg)

    property string _lastProfileError: ""

    function _pickedUrl(dlg) {
        if (!dlg) return ""
        if (dlg.selectedFile !== undefined && dlg.selectedFile) return dlg.selectedFile
        if (dlg.currentFile  !== undefined && dlg.currentFile)  return dlg.currentFile
        return ""
    }

    function openExport() { exportProfileDialog.open() }
    function openImport() { importProfileDialog.open() }

    FileDialog {
        id: exportProfileDialog
        title: qsTr("Export Profile")
        fileMode: FileDialog.SaveFile
        nameFilters: [ "JSON (*.json)" ]
        currentFolder: (root.axisRouter && root.axisRouter.actionConfigDirUrl) ? root.axisRouter.actionConfigDirUrl() : ""
        onAccepted: {
            if (!root.axisRouter || !root.axisRouter.exportProfileToFile) return
            var url = root._pickedUrl(exportProfileDialog)
            var err = root.axisRouter.exportProfileToFile(url)
            if (err && String(err).length > 0) {
                root._lastProfileError = err
                profileErrorDialog.open()
                root.errorOccured(err)
            } else {
                root.exportOk()
            }
        }
    }

    FileDialog {
        id: importProfileDialog
        title: qsTr("Import Profile")
        fileMode: FileDialog.OpenFile
        nameFilters: [ "JSON (*.json)" ]
        currentFolder: (root.axisRouter && root.axisRouter.actionConfigDirUrl) ? root.axisRouter.actionConfigDirUrl() : ""
        onAccepted: {
            if (!root.axisRouter || !root.axisRouter.importProfileFromFile) return
            var url = root._pickedUrl(importProfileDialog)
            var err = root.axisRouter.importProfileFromFile(url)
            if (err && String(err).length > 0) {
                root._lastProfileError = err
                profileErrorDialog.open()
                root.errorOccured(err)
            } else {
                root.importedOk()
            }
        }
    }

    MessageDialog {
        id: profileErrorDialog
        title: qsTr("Profile error")
        text: root._lastProfileError
        buttons: MessageDialog.Ok
    }
}
