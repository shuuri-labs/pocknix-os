import QtQuick
import QtQuick.Controls as QQC2
import Pocknix.Ui

// Primary = the step the screen is for, Danger = it removes or rewrites something, the rest stay
// Secondary. Disabled is an outline in every kind, so a greyed-out primary never reads as live.
QQC2.Button {
    id: control
    enum Kind { Secondary, Primary, Danger }
    property int kind: Button.Secondary
    readonly property color fill: kind === Button.Primary ? Theme.accent
        : kind === Button.Danger ? Theme.negative : Theme.surfaceHigh

    implicitHeight: Theme.touchTarget
    palette.buttonText: !enabled ? Theme.textMuted : kind === Button.Secondary ? Theme.text : Theme.accentText
    background: Rectangle {
        implicitWidth: Theme.touchTarget * 2
        radius: Theme.radius
        color: !control.enabled ? "transparent" : control.down ? Qt.tint(control.fill, "#26ffffff") : control.fill
        border.width: 1
        border.color: control.enabled ? "transparent" : Theme.border
    }
}
