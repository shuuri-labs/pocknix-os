import QtQuick
import QtQuick.Controls as QQC2
import Pocknix.Ui

Rectangle {
    id: badge
    property alias text: label.text
    // neutral | positive | warning | negative | accent
    property string tone: "neutral"
    readonly property color toneColor: Theme.toneColor(tone)

    implicitWidth: label.implicitWidth + Theme.smallSpacing * 4
    implicitHeight: label.implicitHeight + Theme.smallSpacing * 2
    radius: height / 2
    color: Qt.rgba(toneColor.r, toneColor.g, toneColor.b, 0.18)

    QQC2.Label {
        id: label
        anchors.centerIn: parent
        color: badge.toneColor
        font.pointSize: Theme.smallFontSize
        font.bold: true
    }
}
