import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import Pocknix.Ui

// A success that needs nothing from the user: gone after a few seconds or a tap. Not modal and
// takes no focus, so it never blocks a tap or the Steam keyboard. Failures stay in a sheet.
QQC2.Popup {
    id: toast
    property string title
    property string text

    function show(title, text) {
        toast.title = title
        toast.text = text || ""
        hide.restart()
        open()
    }

    parent: QQC2.Overlay.overlay
    width: Math.min(parent ? parent.width - Theme.spacing * 4 : 0, Theme.unit * 28)
    y: parent ? parent.height - height - Theme.spacing * 2 : 0
    modal: false
    dim: false
    focus: false
    closePolicy: QQC2.Popup.NoAutoClose
    padding: Theme.spacing
    background: Rectangle {
        color: Theme.surfaceHigh
        radius: Theme.radius
        border.color: Theme.positive
    }

    // Long enough to read a title and one sentence (Material's snackbar minimum).
    Timer {
        id: hide
        interval: 4000
        onTriggered: toast.close()
    }

    // on the content: Accessible only attaches to an Item, which a Popup is not
    contentItem: ColumnLayout {
        spacing: 0
        Accessible.role: Accessible.AlertMessage
        Accessible.name: toast.title
        TapHandler {
            onTapped: toast.close()
        }
        QQC2.Label {
            Layout.fillWidth: true
            text: toast.title
            font.bold: true
            wrapMode: Text.WordWrap
        }
        QQC2.Label {
            Layout.fillWidth: true
            visible: text !== ""
            text: toast.text
            color: Theme.textMuted
            wrapMode: Text.WordWrap
        }
    }
}
