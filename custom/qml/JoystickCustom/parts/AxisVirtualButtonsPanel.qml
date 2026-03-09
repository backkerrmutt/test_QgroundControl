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

    property var axisRouter:     null
    property var activeJoystick: null

    // Optional label function injected from parent
    // Signature: (axisNum:int) -> string
    property var axisLabelFn: null

    function _axisName(axisNum) {
        if (axisLabelFn) return axisLabelFn(axisNum)
        if (axisRouter && axisRouter.axisLabel) return axisRouter.axisLabel(axisNum)
        return "Axis " + axisNum
    }

    function _axisTitle(axisNum, activePos) {
        var name   = _axisName(axisNum)
        var posStr = (activePos !== undefined && activePos !== null && activePos >= 0)
                     ? ("  (Pos " + activePos + ")") : ""
        return name + posStr + "  (#" + axisNum + ")"
    }

    // refs passed from root
    property var actionModelFn:       null
    property var activePosProvider:   null   // object with get(axisNum)
    property var profileDialogs:      null
    property var removeConfirmDialog: null

    property int  gridColumns:    2
    property real containerWidth: 800
    property bool editMode:       false

    QGCPalette { id: qgcPal; colorGroupEnabled: true }

    ListModel { id: axisModel }

    // ── Custom actions that must always appear in the combo model ────────────
    // (joystick.assignableActionTitles never includes these)
    readonly property var _customActions: ["Servo Control", "Actuator Control"]

    function _actionModel() {
        var base = actionModelFn ? actionModelFn()
                                 : ((activeJoystick && activeJoystick.assignableActionTitles)
                                    ? activeJoystick.assignableActionTitles : [])
        var out = base.slice()
        for (var si = 0; si < _customActions.length; si++) {
            var found = false
            for (var bi = 0; bi < base.length; bi++) {
                if (String(base[bi]).toLowerCase() === _customActions[si].toLowerCase()) {
                    found = true; break
                }
            }
            if (!found) out.push(_customActions[si])
        }
        return out
    }

    // ── Axis card model sync ─────────────────────────────────────────────────
    function _syncAxisModel() {
        if (!axisRouter || !axisRouter.mappedAxes) { axisModel.clear(); return }
        var arr  = axisRouter.mappedAxes
        var want = []
        for (var i = 0; i < arr.length; i++) want.push(Number(arr[i]))

        for (var r = axisModel.count - 1; r >= 0; r--) {
            if (want.indexOf(axisModel.get(r).axis) < 0) axisModel.remove(r)
        }
        for (var j = 0; j < want.length; j++) {
            var a = want[j]; var found = false
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

    function forceResync() { _syncAxisModel(); _commitOrderToCpp() }

    Component.onCompleted: _syncAxisModel()

    onAxisRouterChanged: _syncAxisModel()

    Connections {
        target: axisRouter
        ignoreUnknownSignals: true
        function onMappingsChanged() { Qt.callLater(axisMapBox._syncAxisModel) }
    }

    // ── Drag ghost state ─────────────────────────────────────────────────────
    property bool   _dragging:   false
    property int    _dragAxis:   -1
    property real   _ghostX:     0
    property real   _ghostY:     0
    property real   _ghostW:     0
    property real   _ghostH:     0
    property string _ghostTitle: ""

    function _startGhost(axisNum, cardItem) {
        _dragging = true; _dragAxis = axisNum
        _ghostTitle = axisMapBox._axisTitle(axisNum, -1)
        if (cardItem) {
            var p = ghostLayer.mapFromItem(cardItem, 0, 0)
            _ghostX = p.x; _ghostY = p.y
            _ghostW = cardItem.width; _ghostH = cardItem.height
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
    function _stopGhost() { _dragging = false; _dragAxis = -1 }

    // ════════════════════════════════════════════════════════════════════════
    ColumnLayout {
        anchors.fill:    parent
        anchors.margins: ScreenTools.defaultFontPixelWidth
        spacing:         ScreenTools.defaultFontPixelHeight * 0.7

        // ── Toolbar ───────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: ScreenTools.defaultFontPixelWidth

            QGCLabel {
                Layout.fillWidth: true
                text: qsTr("Assign actions per position (Drag ⋮⋮ to reorder)")
                opacity: 0.9; font.bold: true
            }
            QGCButton { text: qsTr("Export File"); onClicked: { if (profileDialogs) profileDialogs.openExport() } }
            QGCButton { text: qsTr("Import File"); onClicked: { if (profileDialogs) profileDialogs.openImport() } }
            QGCButton {
                text: axisMapBox.editMode ? qsTr("Done") : qsTr("Edit")
                implicitWidth: ScreenTools.defaultFontPixelWidth * 12
                onClicked: axisMapBox.editMode = !axisMapBox.editMode
            }
        }

        // ── Card grid wrapper ─────────────────────────────────────────────
        Item {
            id: gridWrap
            Layout.fillWidth: true
            implicitHeight: axisFlow.implicitHeight
            height:         implicitHeight

            // Ghost preview overlay
            Item {
                id: ghostLayer
                anchors.fill: parent
                z: 99999; visible: axisMapBox._dragging; clip: false

                Rectangle {
                    x: axisMapBox._ghostX; y: axisMapBox._ghostY
                    width: Math.max(120, axisMapBox._ghostW)
                    height: Math.max(80, axisMapBox._ghostH)
                    radius: 10; border.width: 2
                    border.color: Qt.rgba(0.2, 0.85, 0.3, 0.95)
                    color: Qt.rgba(0.10, 0.12, 0.14, 0.92); opacity: 0.92
                    MouseArea { anchors.fill: parent; enabled: false }
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: ScreenTools.defaultFontPixelWidth
                        spacing: ScreenTools.defaultFontPixelHeight * 0.35
                        RowLayout {
                            Layout.fillWidth: true; spacing: ScreenTools.defaultFontPixelWidth * 0.6
                            Rectangle { width: ScreenTools.defaultFontPixelWidth * 0.9; height: width; radius: width/2; color: Qt.rgba(0.2,0.85,0.3,0.95) }
                            QGCLabel { Layout.fillWidth: true; font.bold: true; elide: Text.ElideRight; text: axisMapBox._ghostTitle; color: Qt.rgba(1,1,1,0.95) }
                        }
                        Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(1,1,1,0.14) }
                        QGCLabel { Layout.fillWidth: true; wrapMode: Text.WordWrap; opacity: 0.85; text: qsTr("Drop to reorder cards.") }
                    }
                }
            }

            // Layout metrics (invisible)
            Item {
                id: axisGridMetrics
                anchors.fill: parent; visible: false
                readonly property real fpw: (ScreenTools.defaultFontPixelWidth  > 0 && !isNaN(ScreenTools.defaultFontPixelWidth))  ? ScreenTools.defaultFontPixelWidth  : 8
                readonly property real fph: (ScreenTools.defaultFontPixelHeight > 0 && !isNaN(ScreenTools.defaultFontPixelHeight)) ? ScreenTools.defaultFontPixelHeight : 16
                readonly property real gap:      fpw * 2
                readonly property real sidePad:  fpw * 2
                readonly property real usableW:  Math.max(0, axisFlow.width - sidePad)
                readonly property real minCardPx: Math.min(520, Math.max(fpw * 22, 360))
                readonly property int  cols: Math.max(1, Math.min(2, Math.floor((usableW + gap) / (minCardPx + gap))))
                readonly property real cardW: Math.floor((usableW - Math.max(0, cols - 1) * gap) / cols)
                readonly property real minCardH: fph * 11.0
            }

            // ── Flow layout (cards grow in height dynamically) ────────────
            Flow {
                id: axisFlow
                anchors.left: parent.left; anchors.right: parent.right
                spacing: axisGridMetrics.gap
                height: implicitHeight

                property int draggingIndex: -1

                Repeater {
                    id: cardRepeater
                    model: axisModel

                    // ── Card cell ─────────────────────────────────────────
                    delegate: Item {
                        id: cell
                        width:  axisGridMetrics.cardW
                        height: card.height
                        readonly property int axisNum: axis

                        Rectangle {
                            id: card
                            anchors.left: parent.left; anchors.top: parent.top
                            width: axisGridMetrics.cardW

                            readonly property real _m: ScreenTools.defaultFontPixelWidth

                            readonly property int posCount: {
                                if (!axisRouter) return 0
                                axisRouter.mappingSummaries   // reactive dep
                                return axisRouter.positionsForAxis(cell.axisNum)
                            }

                            readonly property int activePos: {
                                return (activePosProvider && activePosProvider.get)
                                       ? activePosProvider.get(cell.axisNum) : -1
                            }
                            readonly property bool _configured: posCount > 0

                            height: Math.max(cardCol.implicitHeight + _m * 2, axisGridMetrics.minCardH)
                            radius: 10; border.width: 1
                            border.color: Qt.rgba(qgcPal.text.r, qgcPal.text.g, qgcPal.text.b, 0.35)
                            color: Qt.rgba(1,1,1,0.04)

                            property bool dragging: false
                            z:       dragging ? 9999 : 0
                            scale:   dragging ? 1.02 : 1.0
                            opacity: (axisMapBox._dragging && axisMapBox._dragAxis === cell.axisNum) ? 0.25 : 0.98

                            ColumnLayout {
                                id: cardCol
                                anchors.left: parent.left; anchors.right: parent.right
                                anchors.top: parent.top; anchors.margins: card._m
                                spacing: ScreenTools.defaultFontPixelHeight * 0.6

                                // ── Header ───────────────────────────────
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: ScreenTools.defaultFontPixelWidth * 0.7

                                    QGCLabel {
                                        visible: !axisMapBox.editMode
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: ScreenTools.defaultFontPixelWidth * 18
                                        text: axisMapBox._axisTitle(cell.axisNum, card.activePos)
                                        font.pixelSize: ScreenTools.defaultFontPixelHeight * 1.2
                                        font.bold: card._configured; color: qgcPal.text
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
                                            target: axisNameField; property: "text"
                                            value: axisMapBox._axisName(cell.axisNum)
                                            when: !axisNameField.activeFocus
                                        }
                                        QGCLabel {
                                            text: (card.activePos >= 0 ? ("(Pos " + card.activePos + ")  ") : "")
                                                  + "(#" + cell.axisNum + ")"
                                            opacity: 0.75
                                        }
                                    }

                                    // Drag handle
                                    Rectangle {
                                        id: dragHandle
                                        width: ScreenTools.defaultFontPixelWidth * 3.2
                                        height: ScreenTools.defaultFontPixelHeight * 1.8
                                        radius: 6; color: Qt.rgba(1,1,1,0.06)
                                        border.width: 1; border.color: Qt.rgba(1,1,1,0.10)
                                        opacity: axisMapBox.editMode ? 1.0 : 0.25
                                        QGCLabel { anchors.centerIn: parent; text: "⋮⋮"; opacity: 0.8 }
                                        MouseArea {
                                            anchors.fill: parent
                                            enabled: axisMapBox.editMode
                                            hoverEnabled: true; preventStealing: true
                                            propagateComposedEvents: false
                                            onPressed: {
                                                card.dragging = true; axisFlow.draggingIndex = index
                                                axisMapBox._startGhost(cell.axisNum, card)
                                                axisMapBox._moveGhost(dragHandle, mouseX, mouseY)
                                            }
                                            onPositionChanged: {
                                                if (axisFlow.draggingIndex < 0) return
                                                axisMapBox._moveGhost(dragHandle, mouseX, mouseY)
                                                var p = axisFlow.mapFromItem(dragHandle, mouseX, mouseY)
                                                var toIndex = -1
                                                for (var ci = 0; ci < cardRepeater.count; ci++) {
                                                    var it = cardRepeater.itemAt(ci)
                                                    if (!it) continue
                                                    var ip = axisFlow.mapFromItem(it, 0, 0)
                                                    if (p.x >= ip.x && p.x < ip.x + it.width &&
                                                        p.y >= ip.y && p.y < ip.y + it.height) {
                                                        toIndex = ci; break
                                                    }
                                                }
                                                if (toIndex < 0) toIndex = axisFlow.draggingIndex
                                                if (toIndex < 0) toIndex = 0
                                                if (toIndex >= axisModel.count) toIndex = axisModel.count - 1
                                                var fromIndex = axisFlow.draggingIndex
                                                if (fromIndex === toIndex) return
                                                axisModel.move(fromIndex, toIndex, 1)
                                                axisFlow.draggingIndex = toIndex
                                            }
                                            onReleased: {
                                                card.dragging = false; axisFlow.draggingIndex = -1
                                                axisMapBox._stopGhost(); axisMapBox._commitOrderToCpp()
                                            }
                                            onCanceled: {
                                                card.dragging = false; axisFlow.draggingIndex = -1
                                                axisMapBox._stopGhost(); axisMapBox._commitOrderToCpp()
                                            }
                                        }
                                    }

                                    QGCButton {
                                        visible: axisMapBox.editMode
                                        text: qsTr("Remove")
                                        onClicked: {
                                            var t = axisMapBox._axisTitle(cell.axisNum, -1)
                                            if (removeConfirmDialog && removeConfirmDialog.askRemove)
                                                removeConfirmDialog.askRemove(cell.axisNum, t)
                                        }
                                    }
                                } // end header RowLayout

                                // ── Per-position rows ─────────────────────
                                Repeater {
                                    model: card.posCount

                                    // ╔══════════════════════════════════════════════╗
                                    // ║  ONE delegate per position                   ║
                                    // ║  Contains: action combo + repeat + params    ║
                                    // ╚══════════════════════════════════════════════╝
                                    delegate: ColumnLayout {
                                        id: posRow
                                        Layout.fillWidth: true
                                        spacing: ScreenTools.defaultFontPixelHeight * 0.3

                                        readonly property bool _isActive: (index === card.activePos)

                                        // ── Non-reactive action cache ─────────────
                                        // Using imperative update instead of declarative binding
                                        // prevents mappingsChanged from resetting the combo when
                                        // only servo ID/PWM or repeat changes.
                                        property string _storedAction: "No Action"

                                        Component.onCompleted: {
                                            if (!axisRouter) return
                                            var acts = axisRouter.actionsForAxis(cell.axisNum)
                                            _storedAction = (acts && index < acts.length)
                                                            ? String(acts[index]) : "No Action"
                                            Qt.callLater(function() { _syncCombo(_storedAction) })
                                        }

                                        function _syncCombo(actionText) {
                                            if (!actionCombo) return
                                            var mdl = actionCombo.model
                                            if (!mdl || mdl.length === 0) return
                                            var lo = String(actionText).toLowerCase()
                                            for (var k = 0; k < mdl.length; k++) {
                                                if (String(mdl[k]).toLowerCase() === lo) {
                                                    actionCombo.currentIndex = k; return
                                                }
                                            }
                                            // Not in model — keep current index (do NOT reset to 0)
                                        }

                                        Connections {
                                            target: axisRouter
                                            ignoreUnknownSignals: true
                                            function onMappingsChanged() {
                                                if (!axisRouter) return
                                                var acts = axisRouter.actionsForAxis(cell.axisNum)
                                                var newAct = (acts && index < acts.length)
                                                             ? String(acts[index]) : "No Action"
                                                // Guard: only sync combo when action actually changed
                                                if (newAct === posRow._storedAction) return
                                                posRow._storedAction = newAct
                                                posRow._syncCombo(newAct)
                                            }
                                        }

                                        // ── Action row (combo + repeat) ───────────
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: ScreenTools.defaultFontPixelWidth

                                            QGCLabel {
                                                text: "Pos " + index
                                                Layout.minimumWidth: ScreenTools.defaultFontPixelWidth * 7
                                                color: posRow._isActive ? Qt.rgba(0.2, 0.85, 0.3, 1.0) : qgcPal.text
                                                font.bold: posRow._isActive
                                            }

                                            Rectangle {
                                                Layout.fillWidth: true
                                                height: actionCombo.implicitHeight + 2
                                                radius: 6; border.width: 1
                                                border.color: posRow._isActive
                                                              ? Qt.rgba(0.2, 0.85, 0.3, 0.9)
                                                              : Qt.rgba(qgcPal.text.r, qgcPal.text.g,
                                                                        qgcPal.text.b, 0.30)
                                                color: posRow._isActive
                                                       ? Qt.rgba(0.2, 0.85, 0.3, 0.14) : "transparent"

                                                QGCComboBox {
                                                    id: actionCombo
                                                    anchors.fill: parent; anchors.margins: 1
                                                    model: axisMapBox._actionModel()
                                                    // currentIndex set ONLY via _syncCombo()
                                                    // Never use a declarative binding here

                                                    onActivated: (i) => {
                                                        if (!axisRouter) return
                                                        var t = textAt(i)
                                                        // Cache update BEFORE C++ call so that
                                                        // onMappingsChanged guard sees no change
                                                        posRow._storedAction = t
                                                        axisRouter.setActionForAxis(cell.axisNum, index, t)
                                                        // Force repeat off for non-repeatable actions
                                                        var act = AU.assignableActionAtComboIndex(activeJoystick, i)
                                                        var isSpecial = (t === "Servo Control" || t === "Actuator Control")
                                                        if (!isSpecial && (!act || !act.canRepeat))
                                                            axisRouter.setRepeatForAxis(cell.axisNum, index, false)
                                                    }
                                                    background: Rectangle { color: "transparent"; radius: 6 }
                                                }
                                            }

                                            // Repeat checkbox
                                            QGCCheckBox {
                                                id: repeatCheck
                                                text: qsTr("Repeat")
                                                Layout.alignment: Qt.AlignVCenter

                                                readonly property var  _actObj: AU.assignableActionAtComboIndex(
                                                                                    activeJoystick, actionCombo.currentIndex)
                                                readonly property bool _isSpecial: actionCombo.currentText === "Servo Control"
                                                                                   || actionCombo.currentText === "Actuator Control"
                                                enabled: _isSpecial || (!!_actObj && !!_actObj.canRepeat)

                                                checked: {
                                                    if (!axisRouter) return false
                                                    axisRouter.mappingSummaries   // reactive dep
                                                    return axisRouter.repeatForAxis(cell.axisNum, index)
                                                }
                                                onClicked: {
                                                    if (!axisRouter || !enabled) return
                                                    axisRouter.setRepeatForAxis(cell.axisNum, index, checked)
                                                }
                                            }
                                        } // end action RowLayout

                                        // ── Servo / Actuator parameter row ────────
                                        RowLayout {
                                            id: servoRow
                                            Layout.fillWidth:  true
                                            Layout.leftMargin: ScreenTools.defaultFontPixelWidth * 6

                                            readonly property bool isServo:    actionCombo.currentText === "Servo Control"
                                            readonly property bool isActuator: actionCombo.currentText === "Actuator Control"
                                            visible: isServo || isActuator

                                            // Local cache — avoids triggering reactive chain on mappingsChanged
                                            property int localServoId:  9
                                            property int localServoPwm: 1500

                                            function _reload() {
                                                if (!axisRouter) return
                                                localServoId  = axisRouter.servoIdForAxis(cell.axisNum, index)
                                                localServoPwm = axisRouter.servoPwmForAxis(cell.axisNum, index)
                                            }

                                            Component.onCompleted: _reload()

                                            Connections {
                                                target: axisRouter
                                                ignoreUnknownSignals: true
                                                function onServoParamsChanged(changedAxis, changedPos) {
                                                    if (changedAxis !== cell.axisNum || changedPos !== index) return
                                                    servoRow._reload()
                                                }
                                                function onMappingsChanged() { servoRow._reload() }
                                            }

                                            // Label changes based on action type
                                            QGCLabel {
                                                text: servoRow.isActuator ? qsTr("Actuator #:") : qsTr("ID:")
                                                font.pointSize: 9; opacity: 0.7
                                            }
                                            QGCTextField {
                                                id: servoIdField
                                                Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 5
                                                inputMethodHints: Qt.ImhDigitsOnly
                                                onEditingFinished: {
                                                    if (axisRouter)
                                                        axisRouter.setServoIdForAxis(cell.axisNum, index, Number(text))
                                                }
                                                Binding {
                                                    target: servoIdField; property: "text"
                                                    value: String(servoRow.localServoId)
                                                    when: !servoIdField.activeFocus
                                                }
                                            }

                                            QGCLabel {
                                                // Servo: PWM µs | Actuator: value 1000–2000 (→ scaled to -1…+1 by C++)
                                                text: servoRow.isActuator ? qsTr("Value (1000-2000):") : qsTr("PWM:")
                                                font.pointSize: 9; opacity: 0.7; Layout.leftMargin: 4
                                            }
                                            QGCTextField {
                                                id: servoPwmField
                                                Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 7
                                                inputMethodHints: Qt.ImhDigitsOnly
                                                placeholderText: servoRow.isActuator ? "1500" : "1500"
                                                onEditingFinished: {
                                                    if (axisRouter)
                                                        axisRouter.setServoPwmForAxis(cell.axisNum, index, Number(text))
                                                }
                                                Binding {
                                                    target: servoPwmField; property: "text"
                                                    value: String(servoRow.localServoPwm)
                                                    when: !servoPwmField.activeFocus
                                                }
                                            }

                                            // Hint for actuator: 1000=–1, 1500=0, 2000=+1
                                            QGCLabel {
                                                text: qsTr("(1000=−1  1500=0  2000=+1)")
                                                font.pointSize: 8; opacity: 0.5
                                                visible: servoRow.isActuator
                                            }

                                            Item { Layout.fillWidth: true }
                                        } // end servoRow RowLayout

                                    } // end posRow ColumnLayout (delegate)

                                } // end Repeater (positions)

                            } // end cardCol ColumnLayout
                        } // end card Rectangle
                    } // end cell Item (delegate)
                } // end Repeater (cards)
            } // end Flow

        } // end gridWrap Item
    } // end root ColumnLayout
} // end QGCGroupBox
