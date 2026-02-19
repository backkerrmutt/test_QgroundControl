/****************************************************************************
 *
 * JoystickConfigButtons.qml (Custom-ready)
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

    // QGC palette
    QGCPalette {
        id: qgcPal
        colorGroupEnabled: root.enabled
    }

    // Controller (ใช้กับ firmware JS buttons)
    JoystickConfigController {
        id: controller
    }

    property var  activeJoystick: _activeJoystick
    property var  axisRouter: QGroundControl.corePlugin ? QGroundControl.corePlugin.axisActionRouter : null
    property bool joystickAvailable: !!activeJoystick && (activeJoystick.connected === undefined ? true : !!activeJoystick.connected)

    // limit buttons shown (เหมือนของเดิมใน QGC)
    property int _maxButtons: 64

    // =========================
    // ✅ Active pos tracking (from AxisActionRouter::axisActivePosChanged)
    // =========================
    property var _axisPosMap: ({})    // { axisNum: activePos }
    property int _axisPosTick: 0      // force re-evaluate bindings when map changes

    function _getActivePos(axisNum) {
        _axisPosTick
        var v = _axisPosMap[axisNum]

        // fallback: ถ้า map ยังไม่ถูกเติม (เช่น กลับหน้าใหม่) ให้ดึงจาก router ที่เก็บ stableIndex ไว้
        if (v === undefined && axisRouter && axisRouter.activePosForAxis) {
            var p = axisRouter.activePosForAxis(axisNum)
            return (p === undefined || p === null) ? -1 : p
        }
        return (v === undefined) ? -1 : v
    }

    function _axisHasMapping(axisNum) {
        if (!axisRouter) return false
        axisRouter.mappingSummaries // bind to mappingsChanged
        return axisRouter.positionsForAxis(axisNum) > 0
    }

    function _refreshActivePosSnapshot() {
        if (!axisRouter) return

        // วิธีหลัก: ให้ C++ emit snapshot ออกมาเป็น signal axisActivePosChanged(..) เติม map ให้
        if (axisRouter.emitActivePositionSnapshot) {
            axisRouter.emitActivePositionSnapshot()
            return
        }

        // fallback: เติมจาก activePosForAxis แบบอ่านตรง ๆ
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

        // กลับหน้า/เพิ่ง bind joystick แล้วให้ดึง snapshot ทันที
        _refreshActivePosSnapshot()
    }

    Component.onCompleted: Qt.callLater(_syncAxisRouter)

    onActiveJoystickChanged: {
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
        function onActiveVehicleChanged() { Qt.callLater(_syncAxisRouter) }
    }

    Connections {
        target: activeJoystick ? activeJoystick : null
        function onConnectedChanged() { Qt.callLater(_syncAxisRouter) }
        function onDestroyed()        { Qt.callLater(_syncAxisRouter) }
    }

    // รับสัญญาณตำแหน่ง active ของแต่ละ axis จาก C++
    Connections {
        target: axisRouter
        function onAxisActivePosChanged(axis, pos) {
            _axisPosMap[axis] = pos
            _axisPosTick++
        }
        function onMappingsChanged() {
            _axisPosTick++
            Qt.callLater(_refreshActivePosSnapshot)
        }
    }

    // =========================
    // Raw Button pressed display
    // =========================
    Connections {
        target: (activeJoystick && joystickAvailable) ? activeJoystick : null
        onRawButtonPressedChanged: (index, pressed) => {
            if (buttonActionRepeater.itemAt(index)) {
                buttonActionRepeater.itemAt(index).pressed = pressed
            }
            if (jsButtonActionRepeater.itemAt(index)) {
                jsButtonActionRepeater.itemAt(index).pressed = pressed
            }
        }
    }

    // =========================
    // ✅ Page vertical scroll
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

            // ==========================================
            // (A) Standard Button Assignment (ของเดิม QGC)
            // ==========================================
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
                    visible: joystickAvailable && !globals.activeVehicle.supportsJSButton

                    Repeater {
                        id: buttonActionRepeater
                        model: activeJoystick ? Math.min(activeJoystick.totalButtonCount, _maxButtons) : 0

                        Row {
                            spacing: ScreenTools.defaultFontPixelWidth
                            property bool pressed
                            property var  currentAssignableAction: activeJoystick ? activeJoystick.assignableActions.get(buttonActionCombo.currentIndex) : null

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
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
                                Component.onCompleted: {
                                    if (activeJoystick) checked = activeJoystick.getButtonRepeat(modelData)
                                }
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Item { width: ScreenTools.defaultFontPixelWidth * 2; height: 1 }
                        }
                    }
                }
            }

            // ==========================================
            // Firmware JS Buttons (ของเดิม QGC)
            // ==========================================
            Column {
                id: buttonCol
                width: parent.width
                visible: joystickAvailable && globals.activeVehicle.supportsJSButton
                spacing: ScreenTools.defaultFontPixelHeight / 3

                Row {
                    spacing: ScreenTools.defaultFontPixelWidth

                    QGCLabel {
                        horizontalAlignment: Text.AlignHCenter
                        width: ScreenTools.defaultFontPixelHeight * 1.5
                        text: qsTr("#")
                    }
                    QGCLabel {
                        width: ScreenTools.defaultFontPixelWidth * 26
                        text: qsTr("Function: ")
                    }
                    QGCLabel {
                        width: ScreenTools.defaultFontPixelWidth * 26
                        visible: globals.activeVehicle.supportsJSButton
                        text: qsTr("Shift Function: ")
                    }
                }

                Repeater {
                    id: jsButtonActionRepeater
                    model: activeJoystick ? Math.min(activeJoystick.totalButtonCount, _maxButtons) : 0

                    Row {
                        spacing: ScreenTools.defaultFontPixelWidth
                        visible: globals.activeVehicle.supportsJSButton

                        property var parameterName: `BTN${index}_FUNCTION`
                        property var parameterShiftName: `BTN${index}_SFUNCTION`
                        property bool hasFirmwareSupport: controller.parameterExists(-1, parameterName)

                        property bool pressed
                        property var  currentAssignableAction: activeJoystick ? activeJoystick.assignableActions.get(buttonActionCombo.currentIndex) : null

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
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
                                if (fact) fact.value = 0
                                if (fact_shift) fact_shift.value = 0
                            }
                        }

                        Item { width: ScreenTools.defaultFontPixelWidth * 2; height: 1 }

                        QGCLabel {
                            text: qsTr("QGC functions do not support shift actions")
                            width: ScreenTools.defaultFontPixelWidth * 15
                            visible: hasFirmwareSupport
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }

            // ==========================================================
            // (B) Custom: Axis -> Virtual Buttons
            // ==========================================================
            Item { Layout.fillWidth: true; height: ScreenTools.defaultFontPixelHeight }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: qgcPal.text
                opacity: 0.2
            }

            GridLayout {
                id: axisSection
                Layout.fillWidth: true
                columnSpacing: ScreenTools.defaultFontPixelWidth * 2
                rowSpacing: ScreenTools.defaultFontPixelHeight

                readonly property bool _joyOk: !!activeJoystick
                    && (activeJoystick.connected === undefined ? true : activeJoystick.connected)

                visible: _joyOk && !!axisRouter

                // 1 คอลัมน์เมื่อจอแคบ, 2 คอลัมน์เมื่อจอกว้าง
                columns: (vScroll.width < (ScreenTools.defaultFontPixelWidth * 115)) ? 1 : 2

                // ---------- Left (or Top): Calibrate Axis ----------
                QGCGroupBox {
                    id: calibrateBox
                    title: qsTr("Calibrate Axis")

                    // ✅ เขียวเมื่อ selectedAxis มี mapping (calibrate แล้ว + save แล้ว)
                    readonly property bool savedAxis: {
                        if (!axisRouter) return false
                        axisRouter.mappingSummaries
                        return axisRouter.positionsForAxis(axisRouter.selectedAxis) > 0
                    }

                    // ===== Coach state (ใช้เป็น guide เท่านั้น) =====
                    property int desiredPositions: 3   // ผู้ใช้เลือก 1/2/3 ก่อนเริ่ม

                    // ดึงเลขจาก hint เฉพาะตอน calibrating (กันไปจับ axis number หลัง stop)
                    readonly property int capturedCount: {
                        if (!axisRouter || !axisRouter.calibrating) return 0
                        var h = String(axisRouter.calibrationHint || "")
                        var m = h.match(/(\d+)/)
                        return m ? parseInt(m[1]) : 0
                    }

                    readonly property int needStep: {
                        var c = capturedCount
                        if (c < 1) return 1
                        if (c >= desiredPositions) return desiredPositions
                        return c + 1
                    }

                    readonly property bool readyToStop: !!axisRouter && axisRouter.calibrating && (capturedCount >= desiredPositions)

                    // ช่วยบอกผู้ใช้ว่า "ค้างนิ่งอยู่ไหม"
                    property real  _lastNorm: 0
                    property real  _lastChangeMs: 0
                    property bool  _holdingSteady: false

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

                    function _beginCalibrate() {
                        if (!axisRouter) return
                        _lastNorm = axisRouter.selectedAxisNorm
                        _lastChangeMs = Date.now()
                        _holdingSteady = false

                        axisRouter.startCalibration()
                        calibModal.open()
                    }

                    function _cancelCalibrate() {
                        if (!axisRouter) return
                        axisRouter.clearCalibration()
                        calibModal.close()
                    }

                    function _restartCalibrate() {
                        if (!axisRouter) return
                        axisRouter.clearCalibration()
                        axisRouter.startCalibration()
                        _lastNorm = axisRouter.selectedAxisNorm
                        _lastChangeMs = Date.now()
                        _holdingSteady = false
                    }

                    function _stopAndSave() {
                        if (!axisRouter) return
                        axisRouter.stopCalibration()
                        calibModal.close()
                    }

                    // ✅ ถ้า calibration ถูกปิดจากที่อื่น (เช่น disconnect) ให้ปิด modal ด้วย
                    Connections {
                        target: axisRouter
                        function onCalibratingChanged() {
                            if (axisRouter && !axisRouter.calibrating && calibModal.visible) {
                                calibModal.close()
                            }
                        }
                    }

                    Layout.alignment: Qt.AlignTop
                    Layout.fillWidth: (axisSection.columns === 1)
                    Layout.preferredWidth: (axisSection.columns === 1)
                                         ? -1
                                         : Math.max(ScreenTools.defaultFontPixelWidth * 44, vScroll.width * 0.33)

                    // =========================
                    // ✅ MODAL ALERT (block input ทั้งหน้า)
                    // =========================
                    Popup {
                        id: calibModal
                        modal: true
                        focus: true
                        closePolicy: Popup.NoAutoClose

                        // ให้ popup อยู่บน overlay layer ของ Controls
                        parent: Overlay.overlay
                        anchors.centerIn: parent
                        width: Math.min(vScroll.width * 0.92, ScreenTools.defaultFontPixelWidth * 92)

                        // dim + block mouse/scroll
                        Overlay.modal: Rectangle {
                            color: "#000000"
                            opacity: 0.55
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.AllButtons
                                hoverEnabled: true
                                preventStealing: true
                                onWheel: wheel.accepted = true
                            }
                        }

                        background: Rectangle {
                            radius: 12
                            border.width: 1
                            border.color: Qt.rgba(1,1,1,0.14)
                            color: Qt.rgba(0.10, 0.12, 0.14, 0.98)
                        }

                        contentItem: ColumnLayout {
                            id: modalCol
                            anchors.margins: ScreenTools.defaultFontPixelWidth * 1.2
                            spacing: ScreenTools.defaultFontPixelHeight * 0.7

                            // Header
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: ScreenTools.defaultFontPixelWidth

                                Rectangle {
                                    width: ScreenTools.defaultFontPixelWidth * 0.9
                                    height: width
                                    radius: width/2
                                    color: Qt.rgba(0.2, 0.85, 0.3, 0.95)
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    QGCLabel {
                                        text: qsTr("Calibrating Axis %1").arg(axisRouter ? axisRouter.selectedAxis : 0)
                                        font.bold: true
                                    }
                                    QGCLabel {
                                        opacity: 0.75
                                        text: qsTr("Target: %1 position(s)").arg(calibrateBox.desiredPositions)
                                    }
                                }

                                QGCButton {
                                    text: qsTr("Cancel")
                                    onClicked: calibrateBox._cancelCalibrate()
                                }
                            }

                            // Body card
                            Rectangle {
                                Layout.fillWidth: true
                                radius: 10
                                border.width: 1
                                border.color: Qt.rgba(1,1,1,0.10)
                                color: Qt.rgba(1,1,1,0.06)

                                // ✅ สำคัญ: ให้กล่องนี้มีความสูงตามเนื้อหา (แก้ทับปุ่ม/ทับ layout)
                                implicitHeight: bodyCol.implicitHeight + ScreenTools.defaultFontPixelHeight * 1.2

                                ColumnLayout {
                                    id: bodyCol
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

                                    // Holding indicator + progress
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

                                    // Steps
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: ScreenTools.defaultFontPixelHeight * 0.35

                                        // Step 1
                                        RowLayout {
                                            Layout.fillWidth: true
                                            readonly property bool done: calibrateBox.capturedCount >= 1
                                            readonly property bool active: !done && (calibrateBox.needStep === 1)

                                            Rectangle {
                                                width: ScreenTools.defaultFontPixelWidth * 1.2
                                                height: width
                                                radius: width/2
                                                color: done ? Qt.rgba(0.2,0.85,0.3,0.95)
                                                            : (active ? Qt.rgba(0.95,0.75,0.15,0.95) : Qt.rgba(1,1,1,0.18))
                                            }
                                            QGCLabel {
                                                Layout.fillWidth: true
                                                text: done ? qsTr("Step 1 ✓  Hold at Position 1")
                                                           : qsTr("Step 1  Go to Position 1 and hold")
                                            }
                                        }

                                        // Step 2
                                        RowLayout {
                                            Layout.fillWidth: true
                                            visible: calibrateBox.desiredPositions >= 2
                                            readonly property bool done: calibrateBox.capturedCount >= 2
                                            readonly property bool active: !done && (calibrateBox.needStep === 2)

                                            Rectangle {
                                                width: ScreenTools.defaultFontPixelWidth * 1.2
                                                height: width
                                                radius: width/2
                                                color: done ? Qt.rgba(0.2,0.85,0.3,0.95)
                                                            : (active ? Qt.rgba(0.95,0.75,0.15,0.95) : Qt.rgba(1,1,1,0.18))
                                            }
                                            QGCLabel {
                                                Layout.fillWidth: true
                                                text: done ? qsTr("Step 2 ✓  Hold at Position 2")
                                                           : qsTr("Step 2  Go to Position 2 and hold")
                                            }
                                        }

                                        // Step 3
                                        RowLayout {
                                            Layout.fillWidth: true
                                            visible: calibrateBox.desiredPositions >= 3
                                            readonly property bool done: calibrateBox.capturedCount >= 3
                                            readonly property bool active: !done && (calibrateBox.needStep === 3)

                                            Rectangle {
                                                width: ScreenTools.defaultFontPixelWidth * 1.2
                                                height: width
                                                radius: width/2
                                                color: done ? Qt.rgba(0.2,0.85,0.3,0.95)
                                                            : (active ? Qt.rgba(0.95,0.75,0.15,0.95) : Qt.rgba(1,1,1,0.18))
                                            }
                                            QGCLabel {
                                                Layout.fillWidth: true
                                                text: done ? qsTr("Step 3 ✓  Hold at Position 3")
                                                           : qsTr("Step 3  Go to Position 3 and hold")
                                            }
                                        }
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
                                        text: qsTr("Tip: 3-position switch can be used as 2 or 1 positions. Capture only the positions you want, then Stop. If captured wrong, Restart.")
                                    }
                                }
                            }

                            // Footer buttons
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: ScreenTools.defaultFontPixelWidth

                                QGCButton {
                                    text: qsTr("Restart")
                                    onClicked: calibrateBox._restartCalibrate()
                                }

                                Item { Layout.fillWidth: true }

                                QGCButton {
                                    text: calibrateBox.readyToStop ? qsTr("Stop (Save)") : qsTr("Stop")
                                    onClicked: calibrateBox._stopAndSave()
                                }
                            }
                        }
                    }

                    // =========================
                    // Normal box content (ก่อนเริ่ม calibrate)
                    // =========================
                    ColumnLayout {
                        anchors.margins: ScreenTools.defaultFontPixelWidth
                        anchors.fill: parent
                        spacing: ScreenTools.defaultFontPixelHeight * 0.7

                        // Joystick row
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
                                }
                            }
                        }

                        // Axis picker
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
                                              : Qt.rgba(qgcPal.text.r, qgcPal.text.g, qgcPal.text.b, 0.55)

                                color: calibrateBox.savedAxis
                                       ? Qt.rgba(0.2, 0.85, 0.3, 0.14)
                                       : Qt.rgba(1, 1, 1, 1)

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
                                        text: axisPick.currentText
                                        color: calibrateBox.savedAxis
                                               ? Qt.rgba(0.2, 0.85, 0.3, 1.0)
                                               : Qt.rgba(0, 0, 0, 0.90)
                                        verticalAlignment: Text.AlignVCenter
                                        elide: Text.ElideRight
                                        leftPadding: ScreenTools.defaultFontPixelWidth * 0.8
                                        rightPadding: ScreenTools.defaultFontPixelWidth * 2.0
                                        font.bold: calibrateBox.savedAxis
                                    }
                                }
                            }
                        }

                        QGCLabel {
                            Layout.fillWidth: true
                            text: axisRouter ? ("raw: " + axisRouter.selectedAxisRaw
                                               + "   norm: " + Number(axisRouter.selectedAxisNorm).toFixed(3)) : ""
                            opacity: 0.85
                        }

                        QGCCheckBox {
                            text: qsTr("Auto follow axis ที่ขยับ")
                            enabled: !axisRouter || !axisRouter.calibrating
                            checked: axisRouter ? axisRouter.autoSelectAxis : false
                            onClicked: axisRouter.autoSelectAxis = checked
                        }

                        // choose positions
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

                        // Start button only (ให้ไปควบคุมใน modal)
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.defaultFontPixelWidth

                            QGCButton {
                                text: qsTr("Start Calibrate")
                                enabled: !!axisRouter && !axisRouter.calibrating
                                onClicked: calibrateBox._beginCalibrate()
                            }
                        }

                        // Result (หลัง stop)
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


                // ---------- Right (or Bottom): Axis → Virtual Buttons ----------
                QGCGroupBox {
                    title: qsTr("Axis → Virtual Buttons")
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: ScreenTools.defaultFontPixelWidth
                        spacing: ScreenTools.defaultFontPixelHeight * 0.7

                        GridLayout {
                            id: axisGrid
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop

                            // responsive columns (1..3)
                            readonly property real minCardW: ScreenTools.defaultFontPixelWidth * 44
                            columns: {
                                var cs = columnSpacing
                                var n = Math.floor((width + cs) / (minCardW + cs))
                                if (n < 1) n = 1
                                if (n > 3) n = 3
                                return n
                            }

                            // ทำให้การ์ดกว้างเท่ากันทุกใบ
                            readonly property real cardW: {
                                var c = columns
                                var cs = columnSpacing
                                var w = width - Math.max(0, (c - 1)) * cs
                                return (c > 0) ? Math.floor(w / c) : width
                            }

                            columnSpacing: ScreenTools.defaultFontPixelWidth * 2
                            rowSpacing: ScreenTools.defaultFontPixelHeight

                            Repeater {
                                model: axisRouter ? axisRouter.mappedAxes : []

                                delegate: Rectangle {
                                    readonly property real _m: ScreenTools.defaultFontPixelWidth
                                    readonly property int axisNum: modelData

                                    readonly property int posCount: {
                                        if (!axisRouter) return 0
                                        axisRouter.mappingSummaries
                                        return axisRouter.positionsForAxis(axisNum)
                                    }

                                    readonly property var acts: {
                                        if (!axisRouter) return []
                                        axisRouter.mappingSummaries
                                        return axisRouter.actionsForAxis(axisNum)
                                    }

                                    readonly property int activePos: root._getActivePos(axisNum)
                                    readonly property bool _configured: (posCount > 0)

                                    Layout.fillWidth: true
                                    Layout.preferredWidth: axisGrid.cardW
                                    Layout.alignment: Qt.AlignTop
                                    Layout.preferredHeight: cardCol.implicitHeight + (_m * 2)

                                    radius: 10
                                    border.width: 1
                                    border.color: Qt.rgba(qgcPal.text.r, qgcPal.text.g, qgcPal.text.b, 0.55)

                                    // ✅ เอาพื้นหลังเขียวทั้งการ์ดออก
                                    color: qgcPal.windowShade
                                    opacity: 0.96

                                    ColumnLayout {
                                        id: cardCol
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: _m
                                        spacing: ScreenTools.defaultFontPixelHeight * 0.6

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: ScreenTools.defaultFontPixelWidth

                                            QGCLabel {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: ScreenTools.defaultFontPixelWidth * 18
                                                text: "Axis " + axisNum + (activePos >= 0 ? ("  (Pos " + activePos + ")") : "")
                                                font.pixelSize: ScreenTools.defaultFontPixelHeight * 1.2
                                                font.bold: _configured
                                                // ✅ หัวข้อ Axis ไม่ต้องเขียว
                                                color: qgcPal.text
                                                elide: Text.ElideRight
                                            }

                                            QGCButton {
                                                text: qsTr("Remove")
                                                onClicked: axisRouter.removeMapping(axisNum)
                                            }
                                        }

                                        Repeater {
                                            model: posCount

                                            delegate: RowLayout {
                                                Layout.fillWidth: true
                                                spacing: ScreenTools.defaultFontPixelWidth

                                                readonly property bool _activeRow: (index === activePos)

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
                                                                  : Qt.rgba(qgcPal.text.r, qgcPal.text.g, qgcPal.text.b, 0.55)

                                                    // ✅ ไฮไลต์เฉพาะแถวที่ active เหมือนเดิม
                                                    color: _activeRow ? Qt.rgba(0.2, 0.85, 0.3, 0.14) : "transparent"

                                                    QGCComboBox {
                                                        id: actionCombo
                                                        anchors.fill: parent
                                                        anchors.margins: 1
                                                        model: activeJoystick ? activeJoystick.assignableActionTitles : []

                                                        currentIndex: {
                                                            if (!activeJoystick) return 0
                                                            var t = (acts && index < acts.length) ? acts[index] : "No Action"

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

                                                        onActivated: (i) => axisRouter.setActionForAxis(axisNum, index, textAt(i))
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
            } // end axisSection
        } // end contentCol
    } // end vScroll
} // end root
