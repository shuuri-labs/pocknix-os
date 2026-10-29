import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import Pocknix.Ui

// A status read in progress or failed; the page hides what depends on it meanwhile.
ColumnLayout {
    id: loadState
    property bool loading: false
    property string error: ""
    signal retry()

    // A spinner that flashes on a fast read looks like a glitch.
    property bool slow: false
    onLoadingChanged: slow = false
    Timer {
        interval: 400
        running: loadState.loading
        onTriggered: loadState.slow = true
    }

    Layout.fillWidth: true
    spacing: Theme.spacing
    visible: error !== "" || (loading && slow)

    RowLayout {
        visible: loadState.error === ""
        spacing: Theme.spacing
        QQC2.BusyIndicator {
            implicitWidth: Theme.iconSize * 0.6
            implicitHeight: implicitWidth
            running: loadState.loading
        }
        QQC2.Label {
            text: qsTr("Loading…")
            color: Theme.textMuted
        }
    }
    QQC2.Label {
        Layout.fillWidth: true
        visible: loadState.error !== ""
        text: loadState.error
        color: Theme.negative
        wrapMode: Text.WordWrap
    }
    Button {
        visible: loadState.error !== ""
        text: qsTr("Try again")
        onClicked: loadState.retry()
    }
}
