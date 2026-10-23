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
    property string badge
    property string badgeTone: "neutral"
    property bool busy: false
    signal clicked()

    implicitWidth: Theme.tileWidth
    implicitHeight: column.implicitHeight + Theme.spacing * 2
    radius: Theme.radius
    color: tap.pressed ? Theme.surfaceHigh : Theme.surface
    border.width: activeFocus ? 2 : 1
    border.color: activeFocus ? Theme.accent : Theme.border
    activeFocusOnTab: true
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
        StatusBadge {
            Layout.alignment: Qt.AlignHCenter
            visible: tile.badge !== ""
            text: tile.badge
            tone: tile.badgeTone
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
