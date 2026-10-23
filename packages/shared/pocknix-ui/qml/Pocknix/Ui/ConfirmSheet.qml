import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import Pocknix.Ui

// `hold` = press-and-hold to confirm, for steps that rewrite the disk or the bootloader: a stray
// tap cannot start them. An empty `cancelText` leaves one button, for a notice.
QQC2.Popup {
    id: sheet
    property string title
    property string text
    property string confirmText: qsTr("Continue")
    property string cancelText: qsTr("Cancel")
    property bool hold: false
    property bool danger: false
    signal accepted()

    function accept() {
        close()
        accepted()
    }

    parent: QQC2.Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(parent ? parent.width - Theme.spacing * 4 : 0, Theme.unit * 30)
    modal: true
    padding: Theme.spacing * 1.5
    background: Rectangle {
        color: Theme.surface
        radius: Theme.radius
        border.color: Theme.border
    }

    contentItem: ColumnLayout {
        spacing: Theme.spacing

        QQC2.Label {
            Layout.fillWidth: true
            text: sheet.title
            font.bold: true
            font.pointSize: Theme.titleFontSize
            wrapMode: Text.WordWrap
        }
        QQC2.Label {
            Layout.fillWidth: true
            text: sheet.text
            wrapMode: Text.WordWrap
        }
        QQC2.Label {
            Layout.fillWidth: true
            visible: sheet.hold
            text: qsTr("Press and hold to confirm.")
            color: Theme.textMuted
            font.pointSize: Theme.smallFontSize
        }
        RowLayout {
            Layout.alignment: Qt.AlignRight
            spacing: Theme.spacing

            QQC2.Button {
                visible: sheet.cancelText !== ""
                text: sheet.cancelText
                implicitHeight: Theme.touchTarget
                onClicked: sheet.close()
            }
            QQC2.Button {
                id: confirm
                property real held: 0
                text: sheet.confirmText
                implicitHeight: Theme.touchTarget
                palette.button: sheet.danger ? Theme.negative : Theme.accent
                palette.buttonText: Theme.accentText
                onClicked: if (!sheet.hold) sheet.accept()
                onPressedChanged: {
                    if (!sheet.hold)
                        return
                    if (pressed) {
                        fill.start()
                    } else {
                        fill.stop()
                        held = 0
                    }
                }
                onHeldChanged: if (held >= 1) sheet.accept()

                NumberAnimation on held {
                    id: fill
                    running: false
                    from: 0
                    to: 1
                    duration: 1200
                }
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * confirm.held
                    radius: Theme.radius
                    color: Qt.rgba(1, 1, 1, 0.25)
                }
            }
        }
    }
}
