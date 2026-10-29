import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import Pocknix.Ui

// The state comes back from the CLI: a tap on the switch or the row's text only asks, via toggled().
ActionRow {
    id: row
    property bool checked: false
    property bool toggleEnabled: true
    property bool toggleVisible: true
    signal toggled()
    // extra buttons, kept left of the switch
    default property alias extras: extraSlot.data

    tappable: toggleVisible && toggleEnabled
    onTapped: toggled()

    RowLayout {
        id: extraSlot
        spacing: Theme.smallSpacing
    }
    QQC2.Switch {
        visible: row.toggleVisible
        checkable: false
        checked: row.checked
        enabled: row.toggleEnabled
        onClicked: row.toggled()
    }
}
