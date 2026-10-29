import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Pocknix.Ui

// One catalogue entry. `icon` takes a file path or a theme icon name.
Rectangle {
    id: tile
    property alias icon: icon.source
    property string title
    property string subtitle
    property bool checked: false
    property bool busy: false
    signal clicked()

    implicitWidth: Theme.tileWidth
    implicitHeight: column.implicitHeight + Theme.spacing * 2
    radius: Theme.radius
    color: tap.pressed ? Theme.surfaceHigh : Theme.surface
    border.width: activeFocus ? 2 : 1
    border.color: activeFocus ? Theme.accent : Theme.border
    activeFocusOnTab: true
    Accessible.name: title
    Accessible.description: checked ? qsTr("Installed") : ""
    Keys.onReturnPressed: clicked()
    Keys.onSpacePressed: clicked()

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: Theme.spacing
        spacing: Theme.smallSpacing

        Kirigami.Icon {
            id: icon
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: Theme.iconSize * 1.5
            implicitHeight: Theme.iconSize * 1.5
            opacity: tile.busy ? 0.4 : 1
        }
        QQC2.Label {
            Layout.fillWidth: true
            text: tile.title
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
        QQC2.Label {
            Layout.fillWidth: true
            visible: text !== ""
            text: tile.subtitle
            color: Theme.textMuted
            font.pointSize: Theme.smallFontSize
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
        // a grid cell can be taller than this tile: stack from the top so titles line up in a row
        Item {
            Layout.fillHeight: true
        }
    }

    // Drawn, not a theme icon: a symbolic icon takes Plasma's text colour on the desktop.
    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Theme.smallSpacing
        visible: tile.checked
        width: Theme.iconSize * 0.45
        height: width
        radius: width / 2
        color: Theme.positive
        QQC2.Label {
            anchors.centerIn: parent
            text: "\u2713"
            color: Theme.background
            font.bold: true
        }
    }

    QQC2.BusyIndicator {
        anchors.centerIn: parent
        visible: tile.busy
        running: tile.busy
    }

    TapHandler {
        id: tap
        onTapped: tile.clicked()
    }
}
