/****************************************************************************
 *
 * JoystickConfig.qml (Custom Override - customcore)
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

/// Joystick Config (Custom Override)
SetupPage {
    id:                 joystickPage
    pageComponent:      pageComponent
    pageName:           qsTr("Joystick")
    pageDescription:    ""

    readonly property real  _maxButtons:         64
    readonly property real  _attitudeLabelWidth: ScreenTools.defaultFontPixelWidth * 12

    Connections {
        target: joystickManager
        onAvailableJoysticksChanged: {
            if (joystickManager.joysticks.length === 0) {
                summaryButton.checked = true
                setupView.showSummaryPanel()
            }
        }
    }

    Component {
        id: pageComponent

        Item {
            width:  availableWidth
            height: bar.height + joyLoader.height

            readonly property real labelToMonitorMargin: ScreenTools.defaultFontPixelWidth * 3

            // ✅ อย่า assign ทับเอง จะทำให้ binding หลุด
            property var  _activeJoystick: joystickManager.activeJoystick
            property bool _allowJoystickSelection: QGroundControl.corePlugin.options.allowJoystickSelection

            function setupPageCompleted() {
                if (controller && controller.start) {
                    controller.start()
                }
                Qt.callLater(_syncRouter)
            }

            // =========================================================
            // ✅ ใช้ Custom Controller
            // =========================================================
            CustomJoystickConfigController {
                id: controller
            }

            // =========================================================
            // ✅ ผูก Router กับ Active Joystick + Active Vehicle
            // =========================================================
            function _syncRouter() {
                if (!controller || !controller.axisActionRouter) {
                    return
                }
                controller.axisActionRouter.setJoystick(_activeJoystick)
                controller.axisActionRouter.setVehicle(globals.activeVehicle)
            }

            Component.onCompleted: Qt.callLater(_syncRouter)

            Connections {
                target: joystickManager
                function onActiveJoystickChanged() {
                    Qt.callLater(_syncRouter)
                }
            }

            Connections {
                target: globals
                function onActiveVehicleChanged() {
                    Qt.callLater(_syncRouter)
                }
            }

            // =========================================================
            // Tabs (เหมือน core)
            // =========================================================
            QGCTabBar {
                id:             bar
                width:          parent.width
                anchors.top:    parent.top

                Component.onCompleted: {
                    if (_activeJoystick) {
                        if (_activeJoystick.axisCount == 0) {
                            currentIndex = _allowJoystickSelection ? 0 : 1
                        } else {
                            currentIndex = _activeJoystick.calibrated ? 0 : 2
                        }
                    } else {
                        currentIndex = 0
                    }
                }

                QGCTabButton {
                    text:       qsTr("General")
                    visible:    _allowJoystickSelection
                }
                QGCTabButton {
                    text:       qsTr("Button Assigment")
                }
                QGCTabButton {
                    text:       qsTr("Calibration")
                    visible:    _activeJoystick && (_activeJoystick.axisCount != 0)
                }
                QGCTabButton {
                    text:       qsTr("Advanced")
                    visible:    _activeJoystick && (_activeJoystick.axisCount != 0)
                }
            }

            property var pages: [
                "JoystickConfigGeneral.qml",
                "JoystickConfigButtons.qml",
                "JoystickConfigCalibration.qml",
                "JoystickConfigAdvanced.qml"
            ]

            Loader {
                id:             joyLoader
                source:         pages[bar.currentIndex]
                width:          parent.width
                anchors.top:    bar.bottom
            }
        }
    }
}
