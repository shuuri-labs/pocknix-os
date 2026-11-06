import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Pocknix.Ui

// A rail, not a top strip: every panel we ship is landscape, so height is the scarce axis, and
// the left edge is where a thumb rests. It scrolls when the pages outgrow it.
Rectangle {
    id: rail
    // [{ title, icon }]
    property var pages: []
    property int currentIndex: 0

    implicitWidth: Theme.railWidth
    color: Theme.surface

    ListView {
        id: list
        anchors.fill: parent
        anchors.topMargin: Theme.smallSpacing
        model: rail.pages
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        spacing: Theme.smallSpacing

        delegate: Item {
            id: item
            required property var modelData
            required property int index
            readonly property bool current: index === rail.currentIndex

            width: ListView.view.width
            height: Math.max(Theme.touchTarget, column.implicitHeight + Theme.smallSpacing * 2)
            Accessible.role: Accessible.PageTab
            Accessible.name: modelData.title
            Accessible.onPressAction: rail.currentIndex = index

            Column {
                id: column
                anchors.centerIn: parent
                width: parent.width - Theme.smallSpacing * 2
                spacing: Theme.smallSpacing / 2

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Theme.iconSize * 1.4
                    height: Theme.iconSize * 0.8
                    radius: height / 2
                    color: item.current ? Theme.accentSoft : tap.pressed ? Theme.surfaceHigh : "transparent"

                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: Theme.iconSize * 0.55
                        height: width
                        source: item.modelData.icon || "application-x-executable"
                        isMask: true
                        color: item.current ? Theme.text : Theme.textMuted
                    }
                }
                QQC2.Label {
                    width: parent.width
                    text: item.modelData.title
                    color: item.current ? Theme.text : Theme.textMuted
                    font.pointSize: Theme.smallFontSize
                    font.bold: item.current
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
            }

            TapHandler {
                id: tap
                onTapped: rail.currentIndex = item.index
            }
        }
    }
}
