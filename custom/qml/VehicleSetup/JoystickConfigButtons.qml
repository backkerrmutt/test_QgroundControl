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
    width: availableWidth
    spacing: ScreenTools.defaultFontPixelHeight

    property var  activeJoystick: _activeJoystick
    property var  axisRouter: QGroundControl.corePlugin ? QGroundControl.corePlugin.axisActionRouter : null

    // ถ้า Joystick มี property connected -> ใช้มัน, ถ้าไม่มีให้ถือว่า true
    property bool joystickAvailable: !!activeJoystick && (activeJoystick.connected === undefined ? true : !!activeJoystick.connected)

    function _syncAxisRouter() {
        if (!axisRouter) return
        axisRouter.setVehicle(globals.activeVehicle)

        // ถ้า remote หลุด ให้เคลียร์ router ไม่ให้ค้าง joystick เก่า
        if (joystickAvailable) axisRouter.setJoystick(activeJoystick)
        else                  axisRouter.setJoystick(null)
    }

    Component.onCompleted: Qt.callLater(_syncAxisRouter)
    onActiveJoystickChanged: Qt.callLater(_syncAxisRouter)
    onAxisRouterChanged: Qt.callLater(_syncAxisRouter)
    onJoystickAvailableChanged: Qt.callLater(_syncAxisRouter)

    Connections {
        target: globals
        function onActiveVehicleChanged() { Qt.callLater(_syncAxisRouter) }
    }

    // ถ้า Joystick มีสัญญาณ connectedChanged/destroyed -> sync ทันที
    Connections {
        target: activeJoystick ? activeJoystick : null
        function onConnectedChanged() { Qt.callLater(_syncAxisRouter) }
        function onDestroyed()        { Qt.callLater(_syncAxisRouter) }
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

    // ==========================================
    // (A) Standard Button Assignment (เดิมของ QGC)
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
                            if(activeJoystick) {
                                var i = find(activeJoystick.buttonActions[modelData])
                                if(i < 0) i = 0
                                currentIndex = i
                            }
                        }

                        Component.onCompleted:  _findCurrentButtonAction()
                        onModelChanged:         _findCurrentButtonAction()
                        onActivated: (index) => { activeJoystick.setButtonAction(modelData, textAt(index)) }
                    }

                    QGCCheckBox {
                        id: repeatCheck
                        text: qsTr("Repeat")
                        enabled: currentAssignableAction && activeJoystick.calibrated && currentAssignableAction.canRepeat
                        onClicked: activeJoystick.setButtonRepeat(modelData, checked)
                        Component.onCompleted: {
                            if(activeJoystick) checked = activeJoystick.getButtonRepeat(modelData)
                        }
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Item { width: ScreenTools.defaultFontPixelWidth * 2; height: 1 }
                }
            }
        }
    }

    // ==========================================
    // Firmware JS Buttons (เดิมของ QGC)
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
                        if(activeJoystick) {
                            currentIndex = find(activeJoystick.buttonActions[modelData])
                            if(currentIndex < 0) currentIndex = 0
                        }
                    }

                    Component.onCompleted:  _findCurrentButtonAction()
                    onModelChanged:         _findCurrentButtonAction()
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
    // (B) Custom: Axis -> Virtual Buttons UI
    // ==========================================================
    Item { Layout.fillWidth: true; height: ScreenTools.defaultFontPixelHeight }

    Rectangle { Layout.fillWidth: true; height: 1; color: qgcPal.text; opacity: 0.2 }

    RowLayout {
        Layout.fillWidth: true
        spacing: ScreenTools.defaultFontPixelWidth * 2
        visible: joystickAvailable && !!axisRouter

        // ---------------- Left: Calibrate Axis ----------------
        QGCGroupBox {
            title: qsTr("Calibrate Axis")
            Layout.preferredWidth: Math.round(root.width * 0.33)   // ✅ ไม่อิง parent.width (กัน loop)
            Layout.fillHeight: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: ScreenTools.defaultFontPixelWidth
                spacing: ScreenTools.defaultFontPixelHeight * 0.7

                RowLayout {
                    Layout.fillWidth: true
                    spacing: ScreenTools.defaultFontPixelWidth

                    QGCLabel { text: qsTr("Axis:") }

                    QGCComboBox {
                        id: axisPick
                        Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 12
                        model: axisRouter ? axisRouter.axisList : []
                        currentIndex: axisRouter ? axisRouter.selectedAxis : 0

                        delegate: ItemDelegate {
                            width: axisPick.width
                            contentItem: Text {
                                readonly property int axisNum: parseInt(modelData)
                                readonly property bool mapped: axisRouter && axisRouter.mappedAxes.indexOf(axisNum) !== -1
                                text: mapped ? ("● " + modelData) : modelData
                                color: mapped ? "#12b886" : qgcPal.text
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }
                        }

                        onActivated: (i) => { axisRouter.selectedAxis = i }
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
                    checked: axisRouter ? axisRouter.autoSelectAxis : false
                    onClicked: axisRouter.autoSelectAxis = checked
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: ScreenTools.defaultFontPixelWidth

                    QGCButton {
                        text: axisRouter && axisRouter.calibrating ? qsTr("Calibrating...") : qsTr("Start Calibrate")
                        enabled: axisRouter ? !axisRouter.calibrating : false
                        onClicked: axisRouter.startCalibration()
                    }
                    QGCButton {
                        text: qsTr("Stop")
                        enabled: axisRouter ? axisRouter.calibrating : false
                        onClicked: axisRouter.stopCalibration()
                    }
                    QGCButton {
                        text: qsTr("Clear")
                        enabled: !!axisRouter
                        onClicked: axisRouter.clearCalibration()
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

                Repeater {
                    model: axisRouter ? axisRouter.calibratedPositions : 0
                    delegate: RowLayout {
                        Layout.fillWidth: true
                        spacing: ScreenTools.defaultFontPixelWidth

                        QGCLabel { text: "Pos " + index; width: ScreenTools.defaultFontPixelWidth * 6 }

                        QGCComboBox {
                            Layout.fillWidth: true
                            model: activeJoystick ? activeJoystick.assignableActionTitles : []

                            currentIndex: {
                                if (!axisRouter || !activeJoystick) return 0
                                var t = axisRouter.pendingActions[index]
                                var i = -1
                                for (var k = 0; k < activeJoystick.assignableActionTitles.length; k++) {
                                    if (String(activeJoystick.assignableActionTitles[k]).toLowerCase() === String(t).toLowerCase()) { i = k; break; }
                                }
                                if (i < 0) i = activeJoystick.assignableActionTitles.indexOf("No Action")
                                return (i >= 0) ? i : 0
                            }

                            onActivated: (i) => axisRouter.setPendingAction(index, textAt(i))
                        }
                    }
                }

                QGCButton {
                    Layout.fillWidth: true
                    enabled: axisRouter ? (axisRouter.calibratedPositions > 0) : false

                    readonly property bool selectedMapped: axisRouter
                        ? (axisRouter.mappedAxes.indexOf(axisRouter.selectedAxis) !== -1)
                        : false

                    text: selectedMapped ? qsTr("Save Mapping") : qsTr("Add Mapping")
                    onClicked: axisRouter.commitSelectedAxisMapping()
                }
            }
        }

        // ---------------- Right: Axis -> Virtual Buttons ----------------
        QGCGroupBox {
            title: qsTr("Axis → Virtual Buttons")
            Layout.fillWidth: true
            Layout.fillHeight: true

            function summaryForAxis(axisNum) {
                if (!axisRouter) return ""
                for (var i = 0; i < axisRouter.mappingSummaries.length; i++) {
                    var s = axisRouter.mappingSummaries[i]
                    if (s.indexOf("Axis " + axisNum + ":") === 0) return s
                }
                return ""
            }

            Item {
                anchors.fill: parent
                anchors.margins: ScreenTools.defaultFontPixelWidth

                GridLayout {
                    anchors.fill: parent
                    columns: 2
                    columnSpacing: ScreenTools.defaultFontPixelWidth * 2
                    rowSpacing: ScreenTools.defaultFontPixelHeight

                    Repeater {
                        model: axisRouter ? axisRouter.mappedAxes : []
                        delegate: Rectangle {
                            Layout.fillWidth: true
                            radius: 10
                            border.width: 1
                            border.color: qgcPal.text
                            color: qgcPal.windowShade
                            opacity: 0.95

                            readonly property int axisNum: modelData
                            readonly property bool expanded: axisRouter && axisRouter.selectedAxis === axisNum

                            // ✅ ทำให้ GridLayout คำนวณความสูงนิ่งขึ้น (ลด rearrange วน)
                            implicitHeight: cardContent.implicitHeight + ScreenTools.defaultFontPixelHeight
                            Layout.preferredHeight: implicitHeight

                            ColumnLayout {
                                id: cardContent
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: ScreenTools.defaultFontPixelWidth
                                spacing: ScreenTools.defaultFontPixelHeight * 0.6

                                RowLayout {
                                    Layout.fillWidth: true

                                    QGCLabel {
                                        text: "Axis " + axisNum
                                        font.pixelSize: ScreenTools.defaultFontPixelHeight * 1.2
                                    }

                                    Item { Layout.fillWidth: true }

                                    QGCButton {
                                        text: expanded ? qsTr("Editing") : qsTr("Edit")
                                        onClicked: axisRouter.selectedAxis = axisNum
                                    }

                                    QGCButton {
                                        text: qsTr("Remove")
                                        onClicked: axisRouter.removeMapping(axisNum)
                                    }
                                }

                                QGCLabel {
                                    Layout.fillWidth: true
                                    visible: !expanded
                                    text: parent.parent.summaryForAxis(axisNum)
                                    wrapMode: Text.WordWrap
                                    opacity: 0.85
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    visible: expanded

                                    Repeater {
                                        model: axisRouter ? axisRouter.calibratedPositions : 0
                                        delegate: RowLayout {
                                            Layout.fillWidth: true
                                            spacing: ScreenTools.defaultFontPixelWidth

                                            QGCLabel { text: "Pos " + index; width: ScreenTools.defaultFontPixelWidth * 6 }

                                            QGCComboBox {
                                                Layout.fillWidth: true
                                                model: activeJoystick ? activeJoystick.assignableActionTitles : []

                                                currentIndex: {
                                                    if (!axisRouter || !activeJoystick) return 0
                                                    var t = axisRouter.pendingActions[index]
                                                    var i = -1
                                                    for (var k = 0; k < activeJoystick.assignableActionTitles.length; k++) {
                                                        if (String(activeJoystick.assignableActionTitles[k]).toLowerCase() === String(t).toLowerCase()) { i = k; break; }
                                                    }
                                                    if (i < 0) i = activeJoystick.assignableActionTitles.indexOf("No Action")
                                                    return (i >= 0) ? i : 0
                                                }

                                                onActivated: (i) => axisRouter.setPendingAction(index, textAt(i))
                                            }
                                        }
                                    }

                                    QGCButton {
                                        Layout.fillWidth: true
                                        text: qsTr("Save Mapping")
                                        enabled: axisRouter ? (axisRouter.calibratedPositions > 0) : false
                                        onClicked: axisRouter.commitSelectedAxisMapping()
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: axisRouter.selectedAxis = axisNum
                                propagateComposedEvents: true
                            }
                        }
                    }
                }
            }
        }
    }
}
