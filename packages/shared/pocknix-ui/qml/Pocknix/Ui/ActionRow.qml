import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import Pocknix.Ui

// The children are the row's control, on the right.
Rectangle {
    id: row
    property string title
    property string description
    property bool busy: false
    default property alias trailing: slot.data

    Layout.fillWidth: true
    implicitHeight: Math.max(Theme.touchTarget, layout.implicitHeight + Theme.spacing * 2)
    radius: Theme.radius
    color: Theme.surface

    RowLayout {
        id: layout
        anchors.fill: parent
        anchors.leftMargin: Theme.spacing
        anchors.rightMargin: Theme.spacing
        spacing: Theme.spacing

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            QQC2.Label {
                Layout.fillWidth: true
                text: row.title
                wrapMode: Text.WordWrap
            }
            QQC2.Label {
                Layout.fillWidth: true
                visible: text !== ""
                text: row.description
                color: Theme.textMuted
                font.pointSize: Theme.smallFontSize
                wrapMode: Text.WordWrap
            }
        }
        QQC2.BusyIndicator {
            visible: row.busy
            running: row.busy
            implicitWidth: Theme.touchTarget
            implicitHeight: Theme.touchTarget
        }
        RowLayout {
            id: slot
            spacing: Theme.smallSpacing
        }
    }
}
