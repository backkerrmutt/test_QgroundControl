/****************************************************************************
 *
 * JoystickConfigButtons.qml (Custom-ready, merged)
 * ✅ Ghost Drag Preview + Profile Export/Import
 *
 ****************************************************************************/

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Palette
import QGroundControl.Controls
import QGroundControl.ScreenTools
import QGroundControl.Controllers
import QGroundControl.FactSystem
import QGroundControl.FactControls

ColumnLayout {
    id: root
    width:  availableWidth
    height: availableHeight
    spacing: 0

    property var _activeJoystick: null
    property var injectedAxisRouter: null

    QGCPalette { id: qgcPal; colorGroupEnabled: root.enabled }
    JoystickConfigController { id: controller }

    property var  activeJoystick: _activeJoystick
    property var  axisRouter: (injectedAxisRouter ? injectedAxisRouter
                    : (QGroundControl.corePlugin ? QGroundControl.corePlugin.axisActionRouter : null))

    property bool joystickAvailable: !!activeJoystick
        && (activeJoystick.connected === undefined ? true : !!activeJoystick.connected)

    property int _maxButtons: 64

    function _axisCount() {
        if (!activeJoystick) return 0
        var v = activeJoystick.axisCount
        if (typeof v === "function") return v()
        return (v === undefined || v === null) ? 0 : v
    }

    function _buttonCount() {
        if (!activeJoystick) return 0
        var v = activeJoystick.totalButtonCount
        if (typeof v === "function") return v()
        return (v === undefined || v === null) ? 0 : v
    }

    property int _axisLabelTick: 0
    function _axisLabel(ax) {
        _axisLabelTick
        if (!axisRouter || !axisRouter.axisLabel) return "Axis " + ax
        return axisRouter.axisLabel(ax)
    }

    property var _axisPosMap: ({})
    property int _axisPosTick: 0

    function _getActivePos(axisNum) {
        _axisPosTick
        var v = _axisPosMap[axisNum]
        if (v === undefined && axisRouter && axisRouter.activePosForAxis) {
            var p = axisRouter.activePosForAxis(axisNum)
            return (p === undefined || p === null) ? -1 : p
        }
        return (v === undefined) ? -1 : v
    }

    function _refreshActivePosSnapshot() {
        if (!axisRouter) return
        if (axisRouter.emitActivePositionSnapshot) {
            axisRouter.emitActivePositionSnapshot()
            return
        }
        if (axisRouter.mappedAxes && axisRouter.activePosForAxis) {
            for (var i = 0; i < axisRouter.mappedAxes.length; i++) {
                var ax = axisRouter.mappedAxes[i]
                _axisPosMap[ax] = axisRouter.activePosForAxis(ax)
            }
            _axisPosTick++
        }
    }

    function _syncAxisRouter() {
        if (!axisRouter) return

        axisRouter.setVehicle(globals.activeVehicle)

        if (joystickAvailable) axisRouter.setJoystick(activeJoystick)
        else                  axisRouter.setJoystick(null)

        _refreshActivePosSnapshot()
    }

    Component.onCompleted: Qt.callLater(_syncAxisRouter)

    onActiveJoystickChanged: {
        _axisPosMap = ({})
        _axisPosTick++
        Qt.callLater(_syncAxisRouter)
    }

    onInjectedAxisRouterChanged: {
        _axisPosMap = ({})
        _axisPosTick++
        Qt.callLater(_syncAxisRouter)
    }

    onAxisRouterChanged: {
        _axisPosMap = ({})
        _axisPosTick++
        Qt.callLater(_syncAxisRouter)
    }

    onJoystickAvailableChanged: Qt.callLater(_syncAxisRouter)

    Connections {
        target: globals
        ignoreUnknownSignals: true
        function onActiveVehicleChanged() { Qt.callLater(_syncAxisRouter) }
    }

    Connections {
        target: activeJoystick ? activeJoystick : null
        ignoreUnknownSignals: true
        function onDestroyed(obj) { Qt.callLater(_syncAxisRouter) }
    }

    Connections {
        target: axisRouter
        ignoreUnknownSignals: true
        function onAxisActivePosChanged(axis, pos) {
            _axisPosMap[axis] = pos
            _axisPosTick++
        }
        function onMappingsChanged() {
            _axisPosTick++
            _axisLabelTick++
            Qt.callLater(_refreshActivePosSnapshot)
        }
    }

    Connections {
        target: (activeJoystick && joystickAvailable) ? activeJoystick : null
        ignoreUnknownSignals: true
        function onRawButtonPressedChanged(index, pressed) {
            if (buttonActionRepeater.itemAt(index))    buttonActionRepeater.itemAt(index).pressed = pressed
            if (jsButtonActionRepeater.itemAt(index))  jsButtonActionRepeater.itemAt(index).pressed = pressed
        }
    }

    // =========================
    // Profile UI (dialogs)
    // =========================
    property string _lastProfileError: ""

    function _pickedUrl(dlg) {
        // QtQuick.Dialogs FileDialog may expose selectedFile or currentFile depending on Qt version
        if (!dlg) return ""
        if (dlg.selectedFile !== undefined && dlg.selectedFile) return dlg.selectedFile
        if (dlg.currentFile  !== undefined && dlg.currentFile)  return dlg.currentFile
        return ""
    }

    FileDialog {
        id: exportProfileDialog
        title: qsTr("Export Profile")
        fileMode: FileDialog.SaveFile
        nameFilters: [ "JSON (*.json)" ]
        onAccepted: {
            if (!axisRouter || !axisRouter.exportProfileToFile) return
            var url = root._pickedUrl(exportProfileDialog)
            var err = axisRouter.exportProfileToFile(url)
            if (err && String(err).length > 0) {
                _lastProfileError = err
                profileErrorDialog.open()
            }
        }
    }

    FileDialog {
        id: importProfileDialog
        title: qsTr("Import Profile")
        fileMode: FileDialog.OpenFile
        nameFilters: [ "JSON (*.json)" ]
        onAccepted: {
            if (!axisRouter || !axisRouter.importProfileFromFile) return
            var url = root._pickedUrl(importProfileDialog)
            var err = axisRouter.importProfileFromFile(url)
            if (err && String(err).length > 0) {
                _lastProfileError = err
                profileErrorDialog.open()
            } else {
                Qt.callLater(_refreshActivePosSnapshot)
                Qt.callLater(axisMapBox._syncAxisModel)
            }
        }
    }

    MessageDialog {
        id: profileErrorDialog
        title: qsTr("Profile error")
        text: _lastProfileError
        buttons: MessageDialog.Ok
    }

    Dialog {
        id: profileJsonDialog
        modal: true
        title: qsTr("Profile JSON")
        standardButtons: Dialog.Close
        width: Math.min(root.width * 0.92, ScreenTools.defaultFontPixelWidth * 120)
        height: Math.min(root.height * 0.85, ScreenTools.defaultFontPixelHeight * 28)

        property string jsonText: ""

        ColumnLayout {
            anchors.fill: parent
            spacing: ScreenTools.defaultFontPixelHeight * 0.6

            TextArea {
                id: profileJsonArea
                Layout.fillWidth: true
                Layout.fillHeight: true
                readOnly: true
                wrapMode: TextArea.NoWrap
                selectByMouse: true
                text: profileJsonDialog.jsonText
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: ScreenTools.defaultFontPixelWidth

                QGCButton { text: qsTr("Select all"); onClicked: profileJsonArea.selectAll() }
                Item { Layout.fillWidth: true }
            }
        }
    }

    // =========================
    // Scroll container
    // =========================
    QGCFlickable {
        id: vScroll
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        flickableDirection: Flickable.VerticalFlick
        contentWidth: width
        contentHeight: contentCol.implicitHeight

        ColumnLayout {
            id: contentCol
            width: vScroll.width
            spacing: ScreenTools.defaultFontPixelHeight

            // =========================
            // Standard Button Assignment (UNCHANGED)
            // =========================
            ColumnLayout {
                id: flowColumn
                Layout.fillWidth: true
                spacing: ScreenTools.defaultFontPixelHeight
                visible: joystickAvailable

                QGCLabel {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: qsTr(" Multiple buttons that have the same action must be pressed simultaneously to invoke the action.")
                }

                Flow {
                    id: buttonFlow
                    Layout.fillWidth: true
                    spacing: ScreenTools.defaultFontPixelWidth
                    visible: joystickAvailable && globals.activeVehicle && !globals.activeVehicle.supportsJSButton

                    Repeater {
                        id: buttonActionRepeater
                        model: activeJoystick ? Math.min(activeJoystick.totalButtonCount, _maxButtons) : 0

                        Row {
                            spacing: ScreenTools.defaultFontPixelWidth
                            property bool pressed
                            property var  currentAssignableAction: activeJoystick ? activeJoystick.assignableActions.get(buttonActionCombo.currentIndex) : null

                            Rectangle {
                                Layout.alignment: Qt.AlignVCenter
                                width: ScreenTools.defaultFontPixelHeight * 1.5
                                height: width
                                border.width: 1
                                border.color: qgcPal.text
                                color: pressed ? qgcPal.buttonHighlight : qgcPal.button

                                QGCLabel {
                                    anchors.fill: parent
                                    color: pressed ? qgcPal.buttonHighlightText : qgcPal.buttonText
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: modelData
                                }
                            }

                            QGCComboBox {
                                id: buttonActionCombo
                                width: ScreenTools.defaultFontPixelWidth * 26
                                model: activeJoystick ? activeJoystick.assignableActionTitles : []
                                sizeToContents: true

                                function _findCurrentButtonAction() {
                                    if (activeJoystick) {
                                        var i = find(activeJoystick.buttonActions[modelData])
                                        if (i < 0) i = 0
                                        currentIndex = i
                                    }
                                }

                                Component.onCompleted: _findCurrentButtonAction()
                                onModelChanged:        _findCurrentButtonAction()
                                onActivated: (index) => { activeJoystick.setButtonAction(modelData, textAt(index)) }
                            }

                            QGCCheckBox {
                                id: repeatCheck
                                text: qsTr("Repeat")
                                enabled: currentAssignableAction && activeJoystick.calibrated && currentAssignableAction.canRepeat
                                onClicked: activeJoystick.setButtonRepeat(modelData, checked)
                                Component.onCompleted: { if (activeJoystick) checked = activeJoystick.getButtonRepeat(modelData) }
                                Layout.alignment: Qt.AlignVCenter
                            }

                            Item { width: ScreenTools.defaultFontPixelWidth * 2; height: 1 }
                        }
                    }
                }
            }

            // =========================
            // Firmware JS Buttons (UNCHANGED)
            // =========================
            Column {
                id: buttonCol
                width: parent.width
                visible: joystickAvailable && globals.activeVehicle && globals.activeVehicle.supportsJSButton
                spacing: ScreenTools.defaultFontPixelHeight / 3

                Row {
                    spacing: ScreenTools.defaultFontPixelWidth
                    QGCLabel { horizontalAlignment: Text.AlignHCenter; width: ScreenTools.defaultFontPixelHeight * 1.5; text: qsTr("#") }
                    QGCLabel { width: ScreenTools.defaultFontPixelWidth * 26; text: qsTr("Function: ") }
                    QGCLabel { width: ScreenTools.defaultFontPixelWidth * 26; visible: globals.activeVehicle && globals.activeVehicle.supportsJSButton; text: qsTr("Shift Function: ") }
                }

                Repeater {
                    id: jsButtonActionRepeater
                    model: activeJoystick ? Math.min(activeJoystick.totalButtonCount, _maxButtons) : 0

                    Row {
                        spacing: ScreenTools.defaultFontPixelWidth
                        visible: globals.activeVehicle && globals.activeVehicle.supportsJSButton

                        property var parameterName:      `BTN${index}_FUNCTION`
                        property var parameterShiftName: `BTN${index}_SFUNCTION`
                        property bool hasFirmwareSupport: controller.parameterExists(-1, parameterName)

                        property bool pressed
                        property var  currentAssignableAction: activeJoystick ? activeJoystick.assignableActions.get(buttonActionCombo.currentIndex) : null

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            width: ScreenTools.defaultFontPixelHeight * 1.5
                            height: width
                            border.width: 1
                            border.color: qgcPal.text
                            color: pressed ? qgcPal.buttonHighlight : qgcPal.button

                            QGCLabel {
                                anchors.fill: parent
                                color: pressed ? qgcPal.buttonHighlightText : qgcPal.buttonText
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                text: modelData
                            }
                        }

                        QGCComboBox {
                            id: buttonActionCombo
                            width: ScreenTools.defaultFontPixelWidth * 26

                            property Fact fact:       controller.parameterExists(-1, parameterName) ? controller.getParameterFact(-1, parameterName) : null
                            property Fact fact_shift: controller.parameterExists(-1, parameterShiftName) ? controller.getParameterFact(-1, parameterShiftName) : null
                            property var factOptions: fact ? fact.enumStrings : []

                            model: activeJoystick ? [...activeJoystick.assignableActionTitles, ...factOptions] : []
                            sizeToContents: true

                            function _findCurrentButtonAction() {
                                if (activeJoystick) {
                                    currentIndex = find(activeJoystick.buttonActions[modelData])
                                    if (currentIndex < 0) currentIndex = 0
                                }
                            }

                            Component.onCompleted: _findCurrentButtonAction()
                            onModelChanged:        _findCurrentButtonAction()
                            onActivated: function (optionIndex) {
                                var func = textAt(optionIndex)
                                activeJoystick.setButtonAction(modelData, func)
                                if (fact)       fact.value = 0
                                if (fact_shift) fact_shift.value = 0
                            }
                        }

                        Item { width: ScreenTools.defaultFontPixelWidth * 2; height: 1 }

                        QGCLabel {
                            text: qsTr("QGC functions do not support shift actions")
                            width: ScreenTools.defaultFontPixelWidth * 15
                            visible: hasFirmwareSupport
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }
                }
            }

            Item { Layout.fillWidth: true; height: ScreenTools.defaultFontPixelHeight }

            Rectangle { Layout.fillWidth: true; height: 1; color: qgcPal.text; opacity: 0.2 }

            // =========================
            // Axis -> Virtual Buttons
            // =========================
            GridLayout {
                id: axisSection
                Layout.fillWidth: true
                columnSpacing: ScreenTools.defaultFontPixelWidth * 2
                rowSpacing: ScreenTools.defaultFontPixelHeight

                readonly property bool _joyOk: !!activeJoystick
                    && (activeJoystick.connected === undefined ? true : activeJoystick.connected)

                visible: _joyOk && !!axisRouter
                columns: (vScroll.width < (ScreenTools.defaultFontPixelWidth * 115)) ? 1 : 2

            // ---------- Left: Calibrate Axis ----------
                QGCGroupBox {
                    id: calibrateBox
                    title: qsTr("Calibrate Axis")

                    readonly property bool savedAxis: {
                        if (!axisRouter) return false
                        axisRouter.mappingSummaries
                        return axisRouter.positionsForAxis(axisRouter.selectedAxis) > 0
                    }

                    property int desiredPositions: 3

                    readonly property int capturedCount: {
                        if (!axisRouter || !axisRouter.calibrating) return 0
                        var h = String(axisRouter.calibrationHint || "")
                        var m = h.match(/Captured\s+(\d+)(?:\/(\d+))?/i)
                        if (m && m[1]) return parseInt(m[1])
                        var m2 = h.match(/(\d+)/)
                        return m2 ? parseInt(m2[1]) : 0
                    }

                    readonly property bool readyToStop: !!axisRouter && axisRouter.calibrating && (capturedCount >= desiredPositions)

                    property real   _lastNorm: 0
                    property double _lastChangeMs: 0
                    property bool   _holdingSteady: false

                    Timer {
                        interval: 100
                        running: !!axisRouter && axisRouter.calibrating
                        repeat: true
                        onTriggered: {
                            var v = axisRouter ? axisRouter.selectedAxisNorm : 0
                            var now = Date.now()
                            if (Math.abs(v - calibrateBox._lastNorm) > 0.02) {
                                calibrateBox._lastNorm = v
                                calibrateBox._lastChangeMs = now
                                calibrateBox._holdingSteady = false
                            } else {
                                calibrateBox._holdingSteady = (now - calibrateBox._lastChangeMs) > 250
                            }
                        }
                    }

                    property bool   _noMoveWarn: false
                    property bool   _moveSeen: false
                    property real   _moveLastNorm: 0
                    property double _moveLastMs: 0

                    Timer {
                        interval: 200
                        running: !!axisRouter && axisRouter.calibrating
                        repeat: true
                        onTriggered: {
                            if (!axisRouter) return

                            if (calibrateBox.readyToStop || calibrateBox.capturedCount > 0) {
                                calibrateBox._noMoveWarn = false
                                return
                            }

                            var v = axisRouter.selectedAxisNorm
                            var now = Date.now()

                            if (Math.abs(v - calibrateBox._moveLastNorm) > 0.03) {
                                calibrateBox._moveLastNorm = v
                                calibrateBox._moveLastMs = now
                                calibrateBox._moveSeen = true
                                calibrateBox._noMoveWarn = false
                            } else {
                                if (!calibrateBox._moveSeen && (now - calibrateBox._moveLastMs) > 2500) {
                                    calibrateBox._noMoveWarn = true
                                }
                                if (!calibrateBox._moveSeen && (now - calibrateBox._moveLastMs) > 20000 && calibrateBox.capturedCount === 0) {
                                    axisRouter.clearCalibration()
                                }
                            }
                        }
                    }

                    Layout.alignment: Qt.AlignTop
                    Layout.fillWidth: (axisSection.columns === 1)
                    Layout.preferredWidth: (axisSection.columns === 1)
                                         ? -1
                                         : Math.max(ScreenTools.defaultFontPixelWidth * 44, vScroll.width * 0.33)

                    // Modal overlay while calibrating
                    Item {
                        id: calibLockLayer
                        parent: root
                        anchors.fill: parent
                        z: 999999
                        visible: !!axisRouter && axisRouter.calibrating

                        Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.55 }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.AllButtons
                            hoverEnabled: true
                            preventStealing: true
                            onWheel: wheel.accepted = true
                        }

                        Rectangle {
                            id: modalCard
                            property real pad: ScreenTools.defaultFontPixelWidth * 1.2

                            width: Math.min(root.width * 0.92, ScreenTools.defaultFontPixelWidth * 92)
                            height: Math.min(root.height * 0.88, modalContent.implicitHeight + (pad * 2))

                            anchors.centerIn: parent
                            radius: 12
                            border.width: 1
                            border.color: Qt.rgba(1,1,1,0.14)
                            color: Qt.rgba(0.10, 0.12, 0.14, 0.98)

                            Keys.onEscapePressed: { if (axisRouter) axisRouter.clearCalibration() }

                            Flickable {
                                id: modalFlick
                                anchors.fill: parent
                                anchors.margins: modalCard.pad
                                clip: true
                                contentWidth: width
                                contentHeight: modalContent.implicitHeight
                                interactive: contentHeight > height
                                flickableDirection: Flickable.VerticalFlick

                                ColumnLayout {
                                    id: modalContent
                                    width: modalFlick.width
                                    spacing: ScreenTools.defaultFontPixelHeight * 0.7

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: ScreenTools.defaultFontPixelWidth

                                        QGCLabel {
                                            Layout.fillWidth: true
                                            font.bold: true
                                            text: qsTr("Calibrating %1 (#%2)")
                                                .arg(axisRouter && axisRouter.axisLabel ? axisRouter.axisLabel(axisRouter.selectedAxis) : "")
                                                .arg(axisRouter ? axisRouter.selectedAxis : 0)
                                        }

                                        QGCButton { text: qsTr("Cancel"); onClicked: { if (axisRouter) axisRouter.clearCalibration() } }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: ScreenTools.defaultFontPixelWidth

                                        QGCLabel { text: qsTr("Axis:") }

                                        QGCComboBox {
                                            id: modalAxisPick
                                            Layout.fillWidth: true
                                            model: axisRouter ? axisRouter.axisList : []
                                            currentIndex: axisRouter ? axisRouter.selectedAxis : 0

                                            onActivated: (i) => {
                                                if (!axisRouter) return
                                                axisRouter.selectedAxis = i
                                                axisRouter.clearCalibration()
                                                axisRouter.startCalibration()

                                                calibrateBox._lastNorm = axisRouter.selectedAxisNorm
                                                calibrateBox._lastChangeMs = Date.now()
                                                calibrateBox._holdingSteady = false

                                                calibrateBox._moveLastNorm = axisRouter.selectedAxisNorm
                                                calibrateBox._moveLastMs = Date.now()
                                                calibrateBox._moveSeen = false
                                                calibrateBox._noMoveWarn = false
                                            }
                                        }
                                    }

                                    QGCLabel {
                                        Layout.fillWidth: true
                                        opacity: 0.85
                                        text: axisRouter
                                              ? ("raw: " + axisRouter.selectedAxisRaw + "   norm: " + Number(axisRouter.selectedAxisNorm).toFixed(3))
                                              : ""
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        radius: 10
                                        border.width: 1
                                        border.color: Qt.rgba(1,1,1,0.10)
                                        color: Qt.rgba(1,1,1,0.06)
                                        implicitHeight: guideCol.implicitHeight + ScreenTools.defaultFontPixelHeight

                                        ColumnLayout {
                                            id: guideCol
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.margins: ScreenTools.defaultFontPixelWidth
                                            spacing: ScreenTools.defaultFontPixelHeight * 0.55

                                            QGCLabel {
                                                Layout.fillWidth: true
                                                wrapMode: Text.WordWrap
                                                font.bold: true
                                                text: qsTr("Guide: Move the switch to each position you want, then hold still briefly.")
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: ScreenTools.defaultFontPixelWidth * 0.6

                                                Rectangle {
                                                    width: ScreenTools.defaultFontPixelWidth * 0.9
                                                    height: width
                                                    radius: width/2
                                                    color: calibrateBox._holdingSteady
                                                           ? Qt.rgba(0.2, 0.85, 0.3, 0.95)
                                                           : Qt.rgba(0.95, 0.75, 0.15, 0.95)
                                                }

                                                QGCLabel {
                                                    Layout.fillWidth: true
                                                    opacity: 0.88
                                                    text: calibrateBox._holdingSteady
                                                          ? qsTr("Holding steady… wait to capture")
                                                          : qsTr("Move to next position, then hold still")
                                                }

                                                QGCLabel {
                                                    opacity: 0.75
                                                    text: qsTr("Captured: %1/%2")
                                                          .arg(calibrateBox.capturedCount)
                                                          .arg(calibrateBox.desiredPositions)
                                                }
                                            }

                                            QGCLabel {
                                                Layout.fillWidth: true
                                                visible: calibrateBox._noMoveWarn && (calibrateBox.capturedCount === 0) && !calibrateBox.readyToStop
                                                color: Qt.rgba(0.95, 0.35, 0.35, 1.0)
                                                wrapMode: Text.WordWrap
                                                text: qsTr("No movement detected. You likely picked the wrong axis. Change Axis above or press Cancel/Restart.")
                                            }

                                            QGCLabel {
                                                Layout.fillWidth: true
                                                visible: calibrateBox.readyToStop
                                                color: Qt.rgba(0.2, 0.85, 0.3, 1.0)
                                                font.bold: true
                                                text: qsTr("Ready! Press Stop to save calibration.")
                                            }

                                            QGCLabel {
                                                Layout.fillWidth: true
                                                opacity: 0.75
                                                wrapMode: Text.WordWrap
                                                text: axisRouter ? axisRouter.calibrationHint : ""
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: ScreenTools.defaultFontPixelWidth

                                        QGCButton {
                                            text: qsTr("Restart")
                                            onClicked: {
                                                if (!axisRouter) return
                                                axisRouter.clearCalibration()
                                                axisRouter.startCalibration()

                                                calibrateBox._lastNorm = axisRouter.selectedAxisNorm
                                                calibrateBox._lastChangeMs = Date.now()
                                                calibrateBox._holdingSteady = false

                                                calibrateBox._moveLastNorm = axisRouter.selectedAxisNorm
                                                calibrateBox._moveLastMs = Date.now()
                                                calibrateBox._moveSeen = false
                                                calibrateBox._noMoveWarn = false
                                            }
                                        }

                                        Item { Layout.fillWidth: true }

                                        QGCButton {
                                            text: qsTr("Stop (Save)")
                                            onClicked: { if (axisRouter) axisRouter.stopCalibration() }
                                        }
                                    }

                                    Item { height: ScreenTools.defaultFontPixelHeight * 0.2 }
                                }
                            }
                        }
                    }

                    // Main calibrate UI
                    ColumnLayout {
                        anchors.margins: ScreenTools.defaultFontPixelWidth
                        anchors.fill: parent
                        spacing: ScreenTools.defaultFontPixelHeight * 0.7

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.defaultFontPixelWidth * 0.8

                            QGCLabel { text: qsTr("Joystick:") }

                            Rectangle {
                                Layout.fillWidth: true
                                height: ScreenTools.defaultFontPixelHeight * 2.2
                                radius: 6
                                border.width: 1
                                border.color: Qt.rgba(1,1,1,0.12)
                                color: Qt.rgba(1,1,1,0.06)

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: ScreenTools.defaultFontPixelWidth * 0.7
                                    spacing: ScreenTools.defaultFontPixelWidth * 0.6

                                    Rectangle {
                                        width: ScreenTools.defaultFontPixelWidth * 0.9
                                        height: width
                                        radius: width/2
                                        color: axisSection._joyOk
                                               ? Qt.rgba(0.2, 0.85, 0.3, 0.95)
                                               : Qt.rgba(0.95, 0.35, 0.35, 0.95)
                                    }

                                    QGCLabel {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: activeJoystick ? activeJoystick.name : qsTr("No joystick")
                                        opacity: axisSection._joyOk ? 1.0 : 0.75
                                    }

                                    RowLayout {
                                        spacing: ScreenTools.defaultFontPixelWidth * 0.5
                                        Layout.alignment: Qt.AlignVCenter

                                        Rectangle {
                                            height: ScreenTools.defaultFontPixelHeight * 1.5
                                            radius: height / 2
                                            color: Qt.rgba(1,1,1,0.08)
                                            border.width: 1
                                            border.color: Qt.rgba(1,1,1,0.12)
                                            implicitWidth: aLabel.implicitWidth + ScreenTools.defaultFontPixelWidth * 1.2

                                            QGCLabel {
                                                id: aLabel
                                                anchors.centerIn: parent
                                                opacity: 0.9
                                                font.pixelSize: ScreenTools.defaultFontPixelHeight * 0.9
                                                text: qsTr("A: %1 axes").arg(root._axisCount())
                                            }
                                        }

                                        Rectangle {
                                            height: ScreenTools.defaultFontPixelHeight * 1.5
                                            radius: height / 2
                                            color: Qt.rgba(1,1,1,0.08)
                                            border.width: 1
                                            border.color: Qt.rgba(1,1,1,0.12)
                                            implicitWidth: bLabel.implicitWidth + ScreenTools.defaultFontPixelWidth * 1.2

                                            QGCLabel {
                                                id: bLabel
                                                anchors.centerIn: parent
                                                opacity: 0.9
                                                font.pixelSize: ScreenTools.defaultFontPixelHeight * 0.9
                                                text: qsTr("B: %1 buttons").arg(root._buttonCount())
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.defaultFontPixelWidth

                            QGCLabel { text: qsTr("Axis:") }

                            Rectangle {
                                Layout.fillWidth: true
                                height: axisPick.implicitHeight + 2
                                radius: 6
                                border.width: 1
                                border.color: calibrateBox.savedAxis
                                              ? Qt.rgba(0.2, 0.85, 0.3, 0.90)
                                              : Qt.rgba(qgcPal.text.r, qgcPal.text.g, qgcPal.text.b, 0.35)
                                color: calibrateBox.savedAxis
                                       ? Qt.rgba(0.2, 0.85, 0.3, 0.12)
                                       : Qt.rgba(1,1,1,0.04)

                                QGCComboBox {
                                    id: axisPick
                                    anchors.fill: parent
                                    anchors.margins: 1

                                    enabled: !axisRouter || !axisRouter.calibrating
                                    model: axisRouter ? axisRouter.axisList : []
                                    currentIndex: axisRouter ? axisRouter.selectedAxis : 0
                                    onActivated: (i) => axisRouter.selectedAxis = i

                                    background: Rectangle { color: "transparent"; radius: 6 }

                                    contentItem: QGCLabel {
                                        text: axisRouter
                                              ? (root._axisLabel(axisPick.currentIndex) + "  (#" + axisPick.currentText + ")")
                                              : axisPick.currentText
                                        color: qgcPal.text
                                        verticalAlignment: Text.AlignVCenter
                                        elide: Text.ElideRight
                                        leftPadding: ScreenTools.defaultFontPixelWidth * 0.8
                                        rightPadding: ScreenTools.defaultFontPixelWidth * 2.0
                                        font.bold: calibrateBox.savedAxis
                                    }

                                    delegate: ItemDelegate {
                                        width: axisPick.width
                                        height: ScreenTools.defaultFontPixelHeight * 2.2

                                        readonly property int ax: Number(modelData)

                                        readonly property bool _saved: {
                                            if (!axisRouter) return false
                                            axisRouter.mappingSummaries
                                            return axisRouter.positionsForAxis(ax) > 0
                                        }

                                        background: Rectangle {
                                            radius: 6
                                            color: highlighted
                                                   ? (_saved ? Qt.rgba(0.2, 0.85, 0.3, 0.18) : Qt.rgba(1,1,1,0.10))
                                                   : (_saved ? Qt.rgba(0.2, 0.85, 0.3, 0.10) : "transparent")
                                            border.width: _saved ? 1 : 0
                                            border.color: _saved ? Qt.rgba(0.2, 0.85, 0.3, 0.10) : "transparent"
                                        }

                                        contentItem: QGCLabel {
                                            text: root._axisLabel(ax) + "  (#" + ax + ")"
                                            color: _saved ? Qt.rgba(0.2, 0.85, 0.3, 1.0) : qgcPal.text
                                            font.bold: _saved
                                            verticalAlignment: Text.AlignVCenter
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }

                        QGCLabel {
                            Layout.fillWidth: true
                            text: axisRouter ? ("raw: " + axisRouter.selectedAxisRaw
                                               + "   norm: " + Number(axisRouter.selectedAxisNorm).toFixed(1)) : ""
                            opacity: 0.85
                        }

                        QGCCheckBox {
                            text: qsTr("Auto follow axis")
                            enabled: !axisRouter || !axisRouter.calibrating
                            checked: axisRouter ? axisRouter.autoSelectAxis : false
                            onClicked: axisRouter.autoSelectAxis = checked
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.defaultFontPixelWidth

                            QGCLabel { text: qsTr("Use positions:") }

                            QGCComboBox {
                                Layout.fillWidth: true
                                enabled: !axisRouter || !axisRouter.calibrating
                                model: [ "1", "2", "3" ]
                                currentIndex: calibrateBox.desiredPositions - 1
                                onActivated: (i) => calibrateBox.desiredPositions = (i + 1)
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.defaultFontPixelWidth

                            QGCButton {
                                text: qsTr("Start Calibrate")
                                enabled: !!axisRouter && !axisRouter.calibrating
                                onClicked: {
                                    if (axisRouter && axisRouter.hasOwnProperty("desiredPositions"))
                                        axisRouter.desiredPositions = calibrateBox.desiredPositions

                                    calibrateBox._moveLastNorm = axisRouter ? axisRouter.selectedAxisNorm : 0
                                    calibrateBox._moveLastMs   = Date.now()
                                    calibrateBox._moveSeen     = false
                                    calibrateBox._noMoveWarn   = false

                                    calibrateBox._lastNorm = axisRouter ? axisRouter.selectedAxisNorm : 0
                                    calibrateBox._lastChangeMs = Date.now()
                                    calibrateBox._holdingSteady = false

                                    axisRouter.startCalibration()
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: axisRouter ? (axisRouter.calibratedPositions > 0) : false

                            QGCLabel { text: axisRouter ? (qsTr("Detected positions: ") + axisRouter.calibratedPositions) : "" }
                            QGCLabel { text: axisRouter ? (qsTr("Centers: ") + axisRouter.calibratedCenters.join(", ")) : "" }
                            QGCLabel { text: axisRouter ? (qsTr("Thresholds: ") + axisRouter.calibratedThresholds.join(", ")) : "" }
                            QGCLabel { text: axisRouter ? axisRouter.calibrationHint : ""; opacity: 0.8; wrapMode: Text.WordWrap }
                        }
                    }
                }


                // ---------- Right: Axis → Virtual Buttons (REORDERABLE) ----------
                QGCGroupBox {
                    id: axisMapBox
                    title: qsTr("Axis → Virtual Buttons")
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop

                    property bool editMode: false

                    ListModel { id: axisModel }

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
                        _ghostTitle = (axisRouter && axisRouter.axisLabel ? axisRouter.axisLabel(axisNum) : ("Axis " + axisNum)) + "  (#" + axisNum + ")"
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

                            // ✅ Split buttons (no overlapping dialogs)
                            QGCButton {
                                text: qsTr("View JSON")
                                onClicked: {
                                    if (!axisRouter || !axisRouter.exportProfileJson) return
                                    profileJsonDialog.jsonText = axisRouter.exportProfileJson()
                                    profileJsonDialog.open()
                                }
                            }

                            QGCButton { text: qsTr("Export File"); onClicked: exportProfileDialog.open() }
                            QGCButton { text: qsTr("Import File"); onClicked: importProfileDialog.open() }

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

                                readonly property real gap: ScreenTools.defaultFontPixelWidth * 2

                                // DPI-safe min width to actually allow 2 columns
                                readonly property real minCardPx: Math.max(ScreenTools.defaultFontPixelWidth * 22, 420)
                                readonly property real sidePad: ScreenTools.defaultFontPixelWidth * 4
                                readonly property real usableW: Math.max(0, width - sidePad)

                                readonly property int cols: (usableW >= (minCardPx * 2 + gap)) ? 2 : 1

                                readonly property real cardW: {
                                    var c = cols
                                    var usable = usableW - Math.max(0, c - 1) * gap
                                    return Math.floor(usable / c)
                                }

                                readonly property real cellStepW: cardW + gap
                                readonly property real cellStepH: ScreenTools.defaultFontPixelHeight * 11.0 + gap
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

                                        readonly property int activePos: root._getActivePos(cell.axisNum)
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

                                                Loader {
                                                    Layout.fillWidth: true
                                                    sourceComponent: axisMapBox.editMode ? editTitle : viewTitle

                                                    Component {
                                                        id: viewTitle
                                                        QGCLabel {
                                                            Layout.fillWidth: true
                                                            Layout.minimumWidth: ScreenTools.defaultFontPixelWidth * 18
                                                            text: (axisRouter && axisRouter.axisLabel ? axisRouter.axisLabel(cell.axisNum) : ("Axis " + cell.axisNum))
                                                                  + (card.activePos >= 0 ? ("  (Pos " + card.activePos + ")") : "")
                                                                  + "  (#" + cell.axisNum + ")"
                                                            font.pixelSize: ScreenTools.defaultFontPixelHeight * 1.2
                                                            font.bold: card._configured
                                                            color: qgcPal.text
                                                            elide: Text.ElideRight
                                                        }
                                                    }

                                                    Component {
                                                        id: editTitle
                                                        Item {
                                                            Layout.fillWidth: true
                                                            height: nameEdit.implicitHeight

                                                            QGCTextField {
                                                                id: nameEdit
                                                                anchors.fill: parent
                                                                text: (axisRouter && axisRouter.axisLabel) ? axisRouter.axisLabel(cell.axisNum) : ("Axis " + cell.axisNum)
                                                                placeholderText: qsTr("Axis name…")
                                                                selectByMouse: true
                                                                onEditingFinished: {
                                                                    if (!axisRouter) return
                                                                    if (axisRouter.setAxisLabel) {
                                                                        axisRouter.setAxisLabel(cell.axisNum, text)
                                                                        root._axisLabelTick++
                                                                    }
                                                                }
                                                            }
                                                        }
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
                                                            vScroll.interactive = false

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
                                                            vScroll.interactive = true

                                                            axisMapBox._stopGhost()
                                                            axisMapBox._commitOrderToCpp()
                                                        }

                                                        onCanceled: {
                                                            card.dragging = false
                                                            axisGrid.draggingIndex = -1
                                                            vScroll.interactive = true

                                                            axisMapBox._stopGhost()
                                                            axisMapBox._commitOrderToCpp()
                                                        }
                                                    }
                                                }

                                                QGCButton {
                                                    text: qsTr("Remove")
                                                    onClicked: {
                                                        if (!axisRouter) return
                                                        axisRouter.removeMapping(cell.axisNum)
                                                        Qt.callLater(axisMapBox._syncAxisModel)
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
                                                            model: activeJoystick ? activeJoystick.assignableActionTitles : []

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

                                                            onActivated: (i) => axisRouter.setActionForAxis(cell.axisNum, index, textAt(i))
                                                            background: Rectangle { color: "transparent"; radius: 6 }
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
            }
        }
    }
}
