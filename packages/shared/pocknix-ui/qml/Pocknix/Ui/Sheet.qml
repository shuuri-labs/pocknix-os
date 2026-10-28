import QtQuick
import QtQuick.Controls as QQC2
import Pocknix.Ui

// Every sheet's frame, so a reskin of the sheets is one edit.
QQC2.Popup {
    property real maxWidth: Theme.unit * 32

    parent: QQC2.Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(parent ? parent.width - Theme.spacing * 4 : 0, maxWidth)
    modal: true
    padding: Theme.spacing * 1.5
    background: Rectangle {
        color: Theme.surface
        radius: Theme.radius
        border.color: Theme.border
    }
}
