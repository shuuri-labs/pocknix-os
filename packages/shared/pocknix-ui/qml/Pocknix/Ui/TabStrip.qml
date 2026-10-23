import QtQuick
import QtQuick.Controls as QQC2
import Pocknix.Ui

QQC2.TabBar {
    id: bar
    property var titles: []

    background: Rectangle { color: Theme.surface }

    Repeater {
        model: bar.titles
        QQC2.TabButton {
            id: tab
            required property string modelData
            text: modelData
            implicitHeight: Theme.touchTarget
            font.pointSize: Theme.fontSize
            contentItem: QQC2.Label {
                text: tab.text
                font: tab.font
                color: tab.checked ? Theme.text : Theme.textMuted
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
            background: Rectangle {
                color: tab.pressed ? Theme.surfaceHigh : Theme.surface
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 3
                    visible: tab.checked
                    color: Theme.accent
                }
            }
        }
    }
}
