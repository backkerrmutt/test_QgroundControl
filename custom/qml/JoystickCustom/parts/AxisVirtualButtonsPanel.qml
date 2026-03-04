import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.ScreenTools
import QGroundControl.Palette

import "ActionUtils.js" as AU

QGCGroupBox {
    id: axisMapBox
    title: qsTr("Axis → Virtual Buttons")
    Layout.fillWidth: true
    Layout.alignment: Qt.AlignTop

    property var axisRouter: null
    property var activeJoystick: null

    // Optional label function injected from parent (used to force QML refresh on rename)
    // Signature: (axisNum:int) -> string
    property var axisLabelFn: null

    function _axisName(axisNum) {
        if (axisLabelFn) return axisLabelFn(axisNum)
        if (axisRouter && axisRouter.axisLabel) return axisRouter.axisLabel(axisNum)
        return "Axis " + axisNum
    }

    function _axisTitle(axisNum, activePos) {
        var name = _axisName(axisNum)
        var posStr = (activePos !== undefined && activePos !== null && activePos >= 0) ? ("  (Pos " + activePos + ")") : ""
        return name + posStr + "  (#" + axisNum + ")"
    }

    // functions/refs passed from root
    property var actionModelFn: null
    property var activePosProvider: null      // object with get(axisNum)
    property var profileDialogs: null         // ProfileDialogs.qml instance
    property var removeConfirmDialog: null    // RemoveConfirmDialog.qml instance

    property int gridColumns: 2
    property real containerWidth: 800

    property bool editMode: false

    QGCPalette { id: qgcPal; colorGroupEnabled: true }

    ListModel { id: axisModel }

    function _actionModel() {
        if (actionModelFn) return actionModelFn()
        // fallback
        return (activeJoystick && activeJoystick.assignableActionTitles) ? activeJoystick.assignableActionTitles : []
    }

    function _syncAxisModel() {
        if (!axisRouter || !axisRouter.mappedAxes) {
            axisModel.clear()
            return
        }

        var arr = axisRouter.mappedAxes
        var want = []
        for (var i = 0; i < arr.length; i++) want.push(Number(arr[i]))

        for (var r = axisModel.count - 1; r >= 0; r--) {
            var ax = axisModel.get(r).axis
            if (want.indexOf(ax) < 0) axisModel.remove(r)
        }

        for (var j = 0; j < want.length; j++) {
            var a = want[j]
            var found = false
            for (var k = 0; k < axisModel.count; k++) {
                if (axisModel.get(k).axis === a) { found = true; break }
            }
            if (!found) axisModel.append({ axis: a })
        }
    }

    function _commitOrderToCpp() {
        if (!axisRouter || !axisRouter.setCardOrder) return
        var out = []
        for (var i = 0; i < axisModel.count; i++) out.push(axisModel.get(i).axis)
        axisRouter.setCardOrder(out)
    }

    function forceResync() {
        _syncAxisModel()
        _commitOrderToCpp()
    }

    Component.onCompleted: _syncAxisModel()

    Connections {
        target: axisRouter
        ignoreUnknownSignals: true
        function onMappingsChanged() { Qt.callLater(axisMapBox._syncAxisModel) }
    }

    // Ghost preview state
    property bool   _dragging: false
    property int    _dragAxis: -1
    property real   _ghostX: 0
    property real   _ghostY: 0
    property real   _ghostW: 0
    property real   _ghostH: 0
    property string _ghostTitle: ""

    function _startGhost(axisNum, cardItem) {
        _dragging = true
        _dragAxis = axisNum
        _ghostTitle = axisMapBox._axisTitle(axisNum, -1)
        if (cardItem) {
            var p = ghostLayer.mapFromItem(cardItem, 0, 0)
            _ghostX = p.x
            _ghostY = p.y
            _ghostW = cardItem.width
            _ghostH = cardItem.height
        } else {
            _ghostW = ScreenTools.defaultFontPixelWidth * 44
            _ghostH = ScreenTools.defaultFontPixelHeight * 10
        }
    }

    function _moveGhost(fromItem, xInItem, yInItem) {
        if (!_dragging) return
        var p = ghostLayer.mapFromItem(fromItem, xInItem, yInItem)
        _ghostX = p.x - (_ghostW * 0.35)
        _ghostY = p.y - (ScreenTools.defaultFontPixelHeight * 1.2)
    }

    function _stopGhost() {
        _dragging = false
        _dragAxis = -1
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: ScreenTools.defaultFontPixelWidth
        spacing: ScreenTools.defaultFontPixelHeight * 0.7

        RowLayout {
            Layout.fillWidth: true
            spacing: ScreenTools.defaultFontPixelWidth

            QGCLabel {
                Layout.fillWidth: true
                text: qsTr("Assign actions per position (Drag ⋮⋮ to reorder)")
                opacity: 0.9
                font.bold: true
            }

            QGCButton {
                text: qsTr("Export File")
                onClicked: { if (profileDialogs) profileDialogs.openExport() }
            }
            QGCButton {
                text: qsTr("Import File")
                onClicked: { if (profileDialogs) profileDialogs.openImport() }
            }

            QGCButton {
                text: axisMapBox.editMode ? qsTr("Done") : qsTr("Edit")
                implicitWidth: ScreenTools.defaultFontPixelWidth * 12
                onClicked: axisMapBox.editMode = !axisMapBox.editMode
            }
        }

        Item {
            id: gridWrap
            Layout.fillWidth: true
            implicitHeight: axisGrid.implicitHeight
            height: implicitHeight

            Item {
                id: ghostLayer
                anchors.fill: parent
                z: 99999
                visible: axisMapBox._dragging
                clip: false

                Rectangle {
                    id: ghostCard
                    x: axisMapBox._ghostX
                    y: axisMapBox._ghostY
                    width: Math.max(120, axisMapBox._ghostW)
                    height: Math.max(80, axisMapBox._ghostH)
                    radius: 10
                    border.width: 2
                    border.color: Qt.rgba(0.2, 0.85, 0.3, 0.95)
                    color: Qt.rgba(0.10, 0.12, 0.14, 0.92)
                    opacity: 0.92

                    MouseArea { anchors.fill: parent; enabled: false }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: ScreenTools.defaultFontPixelWidth
                        spacing: ScreenTools.defaultFontPixelHeight * 0.35

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.defaultFontPixelWidth * 0.6

                            Rectangle {
                                width: ScreenTools.defaultFontPixelWidth * 0.9
                                height: width
                                radius: width/2
                                color: Qt.rgba(0.2, 0.85, 0.3, 0.95)
                            }

                            QGCLabel {
                                Layout.fillWidth: true
                                font.bold: true
                                elide: Text.ElideRight
                                text: axisMapBox._ghostTitle
                                color: Qt.rgba(1,1,1,0.95)
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(1,1,1,0.14) }

                        QGCLabel {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            opacity: 0.85
                            text: qsTr("Drop to reorder cards.")
                        }
                    }
                }
            }

            GridView {
                id: axisGrid
                anchors.fill: parent
                clip: false
                interactive: false

                implicitHeight: contentHeight
                height: implicitHeight

                model: axisModel

                readonly property real fpw: (!ScreenTools.defaultFontPixelWidth || isNaN(ScreenTools.defaultFontPixelWidth) || ScreenTools.defaultFontPixelWidth <= 0)
                                           ? 8 : ScreenTools.defaultFontPixelWidth
                readonly property real fph: (!ScreenTools.defaultFontPixelHeight || isNaN(ScreenTools.defaultFontPixelHeight) || ScreenTools.defaultFontPixelHeight <= 0)
                                           ? 16 : ScreenTools.defaultFontPixelHeight

                readonly property real gap: fpw * 2
                readonly property real sidePad: fpw * 2
                readonly property real usableW: Math.max(0, width - sidePad)
                readonly property real minCardPx: Math.min(520, Math.max(fpw * 22, 360))

                readonly property int cols: Math.max(1, Math.min(2,
                    Math.floor((usableW + gap) / (minCardPx + gap))
                ))

                readonly property real cardW: {
                    var c = cols
                    var usable = usableW - Math.max(0, c - 1) * gap
                    return Math.floor(usable / c)
                }

                readonly property real cellStepW: cardW + gap
                readonly property real cellStepH: fph * 11.0 + gap
                readonly property real cardH: cellStepH - gap

                cellWidth:  cellStepW
                cellHeight: cellStepH

                property int draggingIndex: -1

                delegate: Item {
                    id: cell
                    width: axisGrid.cellStepW
                    height: axisGrid.cellStepH

                    readonly property int axisNum: axis

                    Rectangle {
                        id: card
                        anchors.left: parent.left
                        anchors.top: parent.top
                        width: axisGrid.cardW

                        readonly property real _m: ScreenTools.defaultFontPixelWidth

                        readonly property int posCount: {
                            if (!axisRouter) return 0
                            axisRouter.mappingSummaries
                            return axisRouter.positionsForAxis(cell.axisNum)
                        }

                        readonly property var acts: {
                            if (!axisRouter) return []
                            axisRouter.mappingSummaries
                            return axisRouter.actionsForAxis(cell.axisNum)
                        }

                        readonly property int activePos: (activePosProvider && activePosProvider.get) ? activePosProvider.get(cell.axisNum) : -1
                        readonly property bool _configured: (posCount > 0)

                        height: Math.min(axisGrid.cardH,
                                         Math.max(cardCol.implicitHeight + _m * 2,
                                                  ScreenTools.defaultFontPixelHeight * 8))

                        radius: 10
                        border.width: 1
                        border.color: Qt.rgba(qgcPal.text.r, qgcPal.text.g, qgcPal.text.b, 0.35)
                        color: Qt.rgba(1,1,1,0.04)

                        property bool dragging: false
                        z: dragging ? 9999 : 0
                        scale: dragging ? 1.02 : 1.0
                        opacity: (axisMapBox._dragging && axisMapBox._dragAxis === cell.axisNum) ? 0.25 : 0.98

                        ColumnLayout {
                            id: cardCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: card._m
                            spacing: ScreenTools.defaultFontPixelHeight * 0.6

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: ScreenTools.defaultFontPixelWidth * 0.7

                                // Display name (view mode) / rename (edit mode)
                                QGCLabel {
                                    visible: !axisMapBox.editMode
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: ScreenTools.defaultFontPixelWidth * 18
                                    text: axisMapBox._axisTitle(cell.axisNum, card.activePos)
                                    font.pixelSize: ScreenTools.defaultFontPixelHeight * 1.2
                                    font.bold: card._configured
                                    color: qgcPal.text
                                    elide: Text.ElideRight
                                }

                                RowLayout {
                                    visible: axisMapBox.editMode
                                    Layout.fillWidth: true
                                    spacing: ScreenTools.defaultFontPixelWidth * 0.6

                                    QGCTextField {
                                        id: axisNameField
                                        Layout.fillWidth: true
                                        placeholderText: qsTr("Axis name")
                                        maximumLength: 40
                                        onEditingFinished: {
                                            if (!axisRouter || !axisRouter.setAxisLabel) return
                                            axisRouter.setAxisLabel(cell.axisNum, text)
                                        }
                                    }

                                    Binding {
                                        target: axisNameField
                                        property: "text"
                                        value: axisMapBox._axisName(cell.axisNum)
                                        when: !axisNameField.activeFocus
                                    }

                                    QGCLabel {
                                        text: (card.activePos >= 0 ? ("(Pos " + card.activePos + ")  ") : "") + "(#" + cell.axisNum + ")"
                                        opacity: 0.75
                                    }
                                }

                                Rectangle {
                                    id: dragHandle
                                    width: ScreenTools.defaultFontPixelWidth * 3.2
                                    height: ScreenTools.defaultFontPixelHeight * 1.8
                                    radius: 6
                                    color: Qt.rgba(1,1,1,0.06)
                                    border.width: 1
                                    border.color: Qt.rgba(1,1,1,0.10)
                                    opacity: axisMapBox.editMode ? 1.0 : 0.25

                                    QGCLabel { anchors.centerIn: parent; text: "⋮⋮"; opacity: 0.8 }

                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: axisMapBox.editMode
                                        hoverEnabled: true
                                        preventStealing: true
                                        propagateComposedEvents: false

                                        onPressed: {
                                            card.dragging = true
                                            axisGrid.draggingIndex = index

                                            axisMapBox._startGhost(cell.axisNum, card)
                                            axisMapBox._moveGhost(dragHandle, mouseX, mouseY)
                                        }

                                        onPositionChanged: {
                                            if (axisGrid.draggingIndex < 0) return

                                            axisMapBox._moveGhost(dragHandle, mouseX, mouseY)

                                            var p = axisGrid.mapFromItem(dragHandle, mouseX, mouseY)
                                            var cx = p.x + axisGrid.contentX
                                            var cy = p.y + axisGrid.contentY

                                            var toIndex = axisGrid.indexAt(cx, cy)
                                            if (toIndex < 0) {
                                                var col = Math.floor(p.x / axisGrid.cellStepW)
                                                var row = Math.floor(p.y / axisGrid.cellStepH)
                                                if (col < 0) col = 0
                                                if (col >= axisGrid.cols) col = axisGrid.cols - 1
                                                if (row < 0) row = 0
                                                toIndex = row * axisGrid.cols + col
                                            }

                                            if (toIndex < 0) toIndex = 0
                                            if (toIndex >= axisModel.count) toIndex = axisModel.count - 1

                                            var fromIndex = axisGrid.draggingIndex
                                            if (fromIndex === toIndex) return

                                            axisModel.move(fromIndex, toIndex, 1)
                                            axisGrid.draggingIndex = toIndex
                                        }

                                        onReleased: {
                                            card.dragging = false
                                            axisGrid.draggingIndex = -1
                                            axisMapBox._stopGhost()
                                            axisMapBox._commitOrderToCpp()
                                        }

                                        onCanceled: {
                                            card.dragging = false
                                            axisGrid.draggingIndex = -1
                                            axisMapBox._stopGhost()
                                            axisMapBox._commitOrderToCpp()
                                        }
                                    }
                                }

                                QGCButton {
                                    visible: axisMapBox.editMode
                                    text: qsTr("Remove")
                                    onClicked: {
                                        var titleText = axisMapBox._axisTitle(cell.axisNum, -1)
                                        if (removeConfirmDialog && removeConfirmDialog.askRemove) {
                                            removeConfirmDialog.askRemove(cell.axisNum, titleText)
                                        }
                                    }
                                }
                            }

                            Repeater {
                                model: card.posCount
                                delegate: RowLayout {
                                    Layout.fillWidth: true
                                    spacing: ScreenTools.defaultFontPixelWidth
                                    readonly property bool _activeRow: (index === card.activePos)

                                    QGCLabel {
                                        text: "Pos " + index
                                        Layout.minimumWidth: ScreenTools.defaultFontPixelWidth * 7
                                        color: _activeRow ? Qt.rgba(0.2, 0.85, 0.3, 1.0) : qgcPal.text
                                        font.bold: _activeRow
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: actionCombo.implicitHeight + 2
                                        radius: 6
                                        border.width: 1
                                        border.color: _activeRow
                                                      ? Qt.rgba(0.2, 0.85, 0.3, 0.9)
                                                      : Qt.rgba(qgcPal.text.r, qgcPal.text.g, qgcPal.text.b, 0.30)
                                        color: _activeRow ? Qt.rgba(0.2, 0.85, 0.3, 0.14) : "transparent"

                                        QGCComboBox {
                                            id: actionCombo
                                            anchors.fill: parent
                                            anchors.margins: 1
                                            model: axisMapBox._actionModel()

                                            currentIndex: {
                                                if (!activeJoystick) return 0
                                                var t = (card.acts && index < card.acts.length) ? card.acts[index] : "No Action"
                                                var i = -1
                                                for (var k = 0; k < activeJoystick.assignableActionTitles.length; k++) {
                                                    if (String(activeJoystick.assignableActionTitles[k]).toLowerCase()
                                                        === String(t).toLowerCase()) {
                                                        i = k; break
                                                    }
                                                }
                                                if (i < 0) i = activeJoystick.assignableActionTitles.indexOf("No Action")
                                                return (i >= 0) ? i : 0
                                            }

                                            onActivated: (i) => {
                                                if (!axisRouter) return
                                                var t = textAt(i)
                                                axisRouter.setActionForAxis(cell.axisNum, index, t)

                                                // If the selected item is not repeatable (or is a flight-mode append), force repeat off.
                                                var act = AU.assignableActionAtComboIndex(activeJoystick, i)
                                                if (!act || !act.canRepeat) {
                                                    axisRouter.setRepeatForAxis(cell.axisNum, index, false)
                                                }
                                            }
                                            background: Rectangle { color: "transparent"; radius: 6 }
                                        }
                                    }

                                    QGCCheckBox {
                                        text: qsTr("Repeat")
                                        Layout.alignment: Qt.AlignVCenter

                                        // QGC-like: enable by action object at combo index
                                        readonly property var _actObj: AU.assignableActionAtComboIndex(activeJoystick, actionCombo.currentIndex)
                                        enabled: !!_actObj && !!_actObj.canRepeat

                                        checked: {
                                            if (!axisRouter) return false
                                            axisRouter.mappingSummaries
                                            return axisRouter.repeatForAxis(cell.axisNum, index)
                                        }

                                        onClicked: {
                                            if (!axisRouter || !enabled) return
                                            axisRouter.setRepeatForAxis(cell.axisNum, index, checked)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
