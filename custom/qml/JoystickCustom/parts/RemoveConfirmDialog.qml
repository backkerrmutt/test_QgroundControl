import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.ScreenTools
import QGroundControl.Palette

Popup {
    id: root
    modal: true
    focus: true
    z: 999999
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    signal confirmed(int axisNum)

    property int    _pendingAxis: -1
    property string _pendingTitle: ""

    function askRemove(axisNum, titleText) {
        _pendingAxis  = axisNum
        _pendingTitle = titleText
        open()
    }

    QGCPalette { id: qgcPal; colorGroupEnabled: true }

    readonly property real _pad:   ScreenTools.defaultFontPixelWidth * 1.2
    readonly property real _availW: Math.max(360, (parent ? parent.width : 800) - (_pad * 2))
    readonly property real _wantW:  ScreenTools.defaultFontPixelWidth * 80

    padding: _pad
    width: Math.min(_availW, _wantW)

    // IMPORTANT: force height so buttons won't get clipped
    implicitHeight: bodyCol.implicitHeight + (padding * 2)
    height: implicitHeight

    x: Math.round((parent ? (parent.width  - width)  / 2 : 0))
    y: Math.round((parent ? (parent.height - height) / 2 : 0))

    background: Rectangle {
        radius: 12
        border.width: 1
        border.color: Qt.rgba(1,1,1,0.14)
        color: Qt.rgba(0.12, 0.13, 0.15, 0.98)
    }

    Overlay.modal: Rectangle { color: "#000000"; opacity: 0.55 }

    contentItem: ColumnLayout {
        id: bodyCol
        spacing: ScreenTools.defaultFontPixelHeight * 0.7

        RowLayout {
            Layout.fillWidth: true

            QGCLabel {
                Layout.fillWidth: true
                text: qsTr("Confirm remove")
                font.bold: true
                elide: Text.ElideRight
            }

            QGCButton {
                text: "✕"
                Layout.minimumWidth: ScreenTools.defaultFontPixelWidth * 7
                onClicked: root.close()
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(1,1,1,0.10) }

        QGCLabel {
            Layout.fillWidth: true
            text: qsTr("Are you sure you want to remove this mapping?")
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
            maximumLineCount: 1
            font.bold: true
        }

        Rectangle {
            Layout.fillWidth: true
            radius: 10
            border.width: 1
            border.color: Qt.rgba(0.2, 0.85, 0.3, 0.35)
            color: Qt.rgba(0.2, 0.85, 0.3, 0.12)
            implicitHeight: axisName.implicitHeight + ScreenTools.defaultFontPixelHeight * 0.9

            QGCLabel {
                id: axisName
                anchors.fill: parent
                anchors.margins: ScreenTools.defaultFontPixelWidth * 1.1
                text: root._pendingTitle
                font.bold: true
                elide: Text.ElideRight
                maximumLineCount: 1
                verticalAlignment: Text.AlignVCenter
            }
        }

        Item { Layout.fillWidth: true; height: ScreenTools.defaultFontPixelHeight * 0.2 }

        RowLayout {
            Layout.fillWidth: true
            spacing: ScreenTools.defaultFontPixelWidth * 0.8

            Item { Layout.fillWidth: true } // push buttons right

            QGCButton {
                text: qsTr("Close")
                Layout.minimumWidth: ScreenTools.defaultFontPixelWidth * 14
                onClicked: root.close()
            }

            // Green "Remove" button
            QGCButton {
                id: removeBtn
                text: qsTr("Remove")
                Layout.minimumWidth: ScreenTools.defaultFontPixelWidth * 14

                // Force green style
                background: Rectangle {
                    radius: 8
                    color: Qt.rgba(0.2, 0.85, 0.3, 1.0)
                    border.width: 1
                    border.color: Qt.rgba(1,1,1,0.12)
                }

                contentItem: QGCLabel {
                    text: removeBtn.text
                    color: "white"
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }

                onClicked: {
                    var ax = root._pendingAxis
                    root.close()
                    if (ax >= 0) root.confirmed(ax)
                }
            }
        }
    }
}
