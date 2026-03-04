import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

import QGroundControl
import QGroundControl.Controls
import QGroundControl.ScreenTools
import QGroundControl.Palette

QGCGroupBox {
    id: calibrateBox
    title: qsTr("Calibrate Axis")

    property var axisRouter: null
    property var activeJoystick: null
    property var axisLabelFn: null
    property int gridColumns: 2
    property real containerWidth: 800

    QGCPalette { id: qgcPal; colorGroupEnabled: true }

    Layout.alignment: Qt.AlignTop
    Layout.fillWidth: (gridColumns === 1)
    Layout.preferredWidth: (gridColumns === 1)
                           ? -1
                           : Math.max(ScreenTools.defaultFontPixelWidth * 44, containerWidth * 0.33)

    // ===== Axis dropdown labels (FIX) =====
    // Use plain string list model because QGCComboBox can show blank with ListModel roles.
    property var axisPickLabels: []

    function _rebuildAxisPickLabels() {
        if (!axisRouter || !axisRouter.axisList) {
            axisPickLabels = []
            return
        }

        var out = []
        for (var i = 0; i < axisRouter.axisList.length; i++) {
            var axNo = Number(axisRouter.axisList[i])
            var label = axisLabelFn ? axisLabelFn(axNo) : ("Axis " + axNo)
            out.push(label + "  (#" + axNo + ")")
        }

        // Atomic replace (avoid transient empty state)
        axisPickLabels = out
    }

    // ── Joystick wiring ────────────────────────────────────────────────────
    function _wireJoystick() {
        if (axisRouter && axisRouter.setJoystick)
            axisRouter.setJoystick(activeJoystick)
    }

    Component.onCompleted: {
        _wireJoystick()
        _rebuildAxisPickLabels()
    }

    onActiveJoystickChanged: _wireJoystick()
    onAxisRouterChanged:     { _wireJoystick(); _rebuildAxisPickLabels() }

    Connections {
        target: axisRouter
        ignoreUnknownSignals: true
        function onAxisListChanged() { calibrateBox._rebuildAxisPickLabels() }
        function onMappingsChanged() { calibrateBox._rebuildAxisPickLabels() }   // rename triggers this
    }

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
        return 0
    }

    readonly property bool readyToStop: !!axisRouter && axisRouter.calibrating && (capturedCount >= desiredPositions)

    // Simple "steady" detector (UI only)
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

    // ======== Popup for modal dialog ========
    Popup {
        id: calibPopup
        modal: true
        focus: true
        z: 1000000000
        closePolicy: Popup.CloseOnEscape

        readonly property Item _popupParent: (calibrateBox.Window.window && calibrateBox.Window.window.contentItem)
                                            ? calibrateBox.Window.window.contentItem
                                            : calibrateBox
        parent: _popupParent

        readonly property real _pad: ScreenTools.defaultFontPixelWidth * 1.2
        readonly property real _maxW: (parent ? parent.width : calibrateBox.width) * 0.92
        readonly property real _maxH: (parent ? parent.height : calibrateBox.height) * 0.88

        width: Math.min(_maxW, ScreenTools.defaultFontPixelWidth * 92)
        height: Math.min(_maxH, modalContent.implicitHeight + (_pad * 2))

        x: Math.round((parent ? (parent.width  - width)  / 2 : 0))
        y: Math.round((parent ? (parent.height - height) / 2 : 0))

        Overlay.modal: Rectangle { color: "#000000"; opacity: 0.55 }

        background: Rectangle {
            radius: 12
            border.width: 1
            border.color: Qt.rgba(1,1,1,0.14)
            color: Qt.rgba(0.10, 0.12, 0.14, 0.98)
        }

        onClosed: {
            if (axisRouter && axisRouter.calibrating) {
                axisRouter.clearCalibration()
            }
        }

        contentItem: Item {
            anchors.fill: parent
            anchors.margins: calibPopup._pad

            Flickable {
                id: modalFlick
                anchors.fill: parent
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

                        QGCLabel {
                            Layout.fillWidth: true
                            font.bold: true

                            readonly property int axNo: (axisRouter && axisRouter.axisList
                                                        && axisRouter.selectedAxis >= 0
                                                        && axisRouter.selectedAxis < axisRouter.axisList.length)
                                                       ? Number(axisRouter.axisList[axisRouter.selectedAxis])
                                                       : 0
                            readonly property string axLabel: axisLabelFn ? axisLabelFn(axNo) : ("Axis " + axNo)

                            text: qsTr("Calibrating %1 (#%2)").arg(axLabel).arg(axNo)
                        }

                        QGCButton {
                            text: qsTr("Cancel")
                            onClicked: { if (axisRouter) axisRouter.clearCalibration() }
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
                                    radius: width / 2
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
                                text: qsTr("No movement detected. You likely picked the wrong axis. Press Cancel/Restart.")
                            }

                            QGCLabel {
                                Layout.fillWidth: true
                                visible: calibrateBox.readyToStop
                                color: Qt.rgba(0.2, 0.85, 0.3, 1.0)
                                font.bold: true
                                text: qsTr("Ready! Press Done to save calibration.")
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
                            text: qsTr("Done")
                            enabled: calibrateBox.readyToStop
                            onClicked: { if (axisRouter) axisRouter.stopCalibration() }
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: axisRouter
        ignoreUnknownSignals: true
        function onCalibratingChanged() {
            if (!axisRouter) return
            if (axisRouter.calibrating) calibPopup.open()
            else calibPopup.close()
        }
    }

    // Main calibrate UI
    ColumnLayout {
        anchors.margins: ScreenTools.defaultFontPixelWidth
        anchors.fill: parent
        spacing: ScreenTools.defaultFontPixelHeight * 0.7

        RowLayout {
            Layout.fillWidth: true
            spacing: ScreenTools.defaultFontPixelWidth

            QGCLabel { text: qsTr("Axis:") }

            Rectangle {
                Layout.fillWidth: true
                height: axisPick.implicitHeight + 2
                radius: 6
                border.width: 1
                border.color: calibrateBox.savedAxis ? Qt.rgba(0.2, 0.85, 0.3, 0.90)
                                                    : Qt.rgba(qgcPal.text.r, qgcPal.text.g, qgcPal.text.b, 0.35)
                color: calibrateBox.savedAxis ? Qt.rgba(0.2, 0.85, 0.3, 0.12)
                                              : Qt.rgba(1,1,1,0.04)

                QGCComboBox {
                    id: axisPick
                    anchors.fill: parent
                    anchors.margins: 1
                    enabled: !axisRouter || !axisRouter.calibrating

                    // ✅ string-list model (never blank)
                    model: calibrateBox.axisPickLabels

                    // selectedAxis is already "index in axisList"
                    currentIndex: axisRouter ? axisRouter.selectedAxis : 0

                    onActivated: (i) => {
                        if (!axisRouter) return
                        axisRouter.selectedAxis = i
                    }

                    background: Rectangle { color: "transparent"; radius: 6 }
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
            onClicked: { if (axisRouter) axisRouter.autoSelectAxis = checked }
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
            QGCButton {
                text: qsTr("Start Calibrate")
                enabled: !!axisRouter && !axisRouter.calibrating
                onClicked: {
                    if (!axisRouter) return

                    if (axisRouter.hasOwnProperty("desiredPositions"))
                        axisRouter.desiredPositions = calibrateBox.desiredPositions

                    calibrateBox._moveLastNorm = axisRouter.selectedAxisNorm
                    calibrateBox._moveLastMs   = Date.now()
                    calibrateBox._moveSeen     = false
                    calibrateBox._noMoveWarn   = false

                    calibrateBox._lastNorm = axisRouter.selectedAxisNorm
                    calibrateBox._lastChangeMs = Date.now()
                    calibrateBox._holdingSteady = false

                    axisRouter.startCalibration()

                    if (axisRouter.calibrating) calibPopup.open()
                }
            }
        }
    }
}
