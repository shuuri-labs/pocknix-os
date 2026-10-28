import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import Pocknix.Ui

// `hold` = press-and-hold to confirm, for steps that rewrite the disk or the bootloader: a stray
// tap cannot start them. An empty `cancelText` leaves one button, for a notice.
Sheet {
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

    maxWidth: Theme.unit * 30

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

            Button {
                visible: sheet.cancelText !== ""
                text: sheet.cancelText
                onClicked: sheet.close()
            }
            Button {
                id: confirm
                property real held: 0
                text: sheet.confirmText
                kind: sheet.danger ? Button.Danger : Button.Primary
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
