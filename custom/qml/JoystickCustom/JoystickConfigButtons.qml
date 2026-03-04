/****************************************************************************
 *
 * JoystickConfigButtons.qml (Custom-ready, split)
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

import "qrc:/qml/JoystickCustom/parts" as Parts

ColumnLayout {
    id: root
    width:  availableWidth
    height: availableHeight
    spacing: 0

    // injected from JoystickConfig.qml loader
    property var _activeJoystick: null
    property var injectedAxisRouter: null

    QGCPalette { id: qgcPal; colorGroupEnabled: root.enabled }
    JoystickConfigController { id: controller } // core controller (parameterExists, facts, etc.)

    property var  activeJoystick: _activeJoystick
    property var  axisRouter: (injectedAxisRouter ? injectedAxisRouter
                    : (QGroundControl.corePlugin ? QGroundControl.corePlugin.axisActionRouter : null))

    property bool joystickAvailable: !!activeJoystick
        && (activeJoystick.connected === undefined ? true : !!activeJoystick.connected)

    property int _maxButtons: 64

    // -----------------------------
    // Axis label + active position cache
    // -----------------------------
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

    // Action model (append flight modes)
    function _actionModelWithFlightModes() {
        var base = (activeJoystick && activeJoystick.assignableActionTitles) ? activeJoystick.assignableActionTitles : []
        var modes = (axisRouter && axisRouter.allFlightModes) ? axisRouter.allFlightModes() : []
        var out = []
        for (var i=0; i<base.length; i++) out.push(base[i])
        for (var j=0; j<modes.length; j++) {
            if (out.indexOf(modes[j]) < 0) out.push(modes[j])
        }
        return out
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

    // -----------------------------
    // Shared dialogs/components (split out)
    // -----------------------------
    Parts.ProfileDialogs {
        id: profileDialogs
        axisRouter: root.axisRouter
        onImportedOk: {
            Qt.callLater(root._refreshActivePosSnapshot)
            // Axis panel will also re-sync via mappingsChanged, but force is ok
            Qt.callLater(axisPanel.forceResync)
        }
    }

    Parts.RemoveConfirmDialog {
        id: removeConfirmDialog
        parent: root.Window.window ? root.Window.window.contentItem : root
        onConfirmed: (axisNum) => {
            if (!root.axisRouter || !root.axisRouter.removeMapping) return
            root.axisRouter.removeMapping(axisNum)
            Qt.callLater(axisPanel.forceResync)
        }
    }

    // Provider object to avoid child touching root internals
    QtObject {
        id: activePosProvider
        function get(axisNum) { return root._getActivePos(axisNum) }
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
            // Standard Button Assignment
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
                                model: root._actionModelWithFlightModes()
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
            // Firmware JS Buttons
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
                        property var  currentAssignableAction: activeJoystick ? activeJoystick.assignableActions.get(buttonActionCombo1.currentIndex) : null

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
                            id: buttonActionCombo1
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
            // Axis -> Virtual Buttons section (split)
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

                Parts.CalibrateAxisPanel {
                    id: calibratePanel
                    axisRouter: root.axisRouter
                    activeJoystick: root.activeJoystick
                    axisLabelFn: root._axisLabel
                    gridColumns: axisSection.columns
                    containerWidth: vScroll.width
                }

                Parts.AxisVirtualButtonsPanel {
                    id: axisPanel
                    axisRouter: root.axisRouter
                    activeJoystick: root.activeJoystick
                    axisLabelFn: root._axisLabel
                    actionModelFn: root._actionModelWithFlightModes
                    activePosProvider: activePosProvider
                    profileDialogs: profileDialogs
                    removeConfirmDialog: removeConfirmDialog
                    gridColumns: axisSection.columns
                    containerWidth: vScroll.width
                }
            }
        }
    }
}
