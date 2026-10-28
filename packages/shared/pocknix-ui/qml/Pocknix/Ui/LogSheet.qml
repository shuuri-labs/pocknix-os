import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import Pocknix.Ui

// `detached`: the work runs under pocknix-job and survives the app, so the sheet may close mid-run.
Sheet {
    id: sheet
    property Job job
    property string title
    property bool detached: false
    readonly property bool running: job !== null && job.running

    width: parent ? parent.width - Theme.spacing * 2 : 0
    height: parent ? parent.height * 0.85 : 0
    closePolicy: running && !detached ? QQC2.Popup.NoAutoClose : QQC2.Popup.CloseOnEscape

    ListModel { id: lines }

    Connections {
        target: sheet.job
        function onRunningChanged() {
            if (sheet.job.running)
                lines.clear()
        }
        function onLine(text) {
            lines.append({ line: text })
            if (lines.count > 2000)
                lines.remove(0)
            view.positionViewAtEnd()
        }
    }

    contentItem: ColumnLayout {
        spacing: Theme.spacing

        QQC2.Label {
            Layout.fillWidth: true
            text: sheet.title
            font.bold: true
            font.pointSize: Theme.titleFontSize
            elide: Text.ElideRight
        }
        QQC2.Label {
            Layout.fillWidth: true
            text: !sheet.job ? ""
                : sheet.running ? (sheet.job.text || qsTr("Working…"))
                : sheet.job.exitCode === 0 ? qsTr("Done") : sheet.job.error
            color: !sheet.running && sheet.job && sheet.job.exitCode !== 0 ? Theme.negative : Theme.text
            wrapMode: Text.WordWrap
        }
        QQC2.ProgressBar {
            Layout.fillWidth: true
            visible: sheet.running
            indeterminate: !sheet.job || sheet.job.progress < 0
            value: sheet.job ? Math.max(0, sheet.job.progress) : 0
        }
        ListView {
            id: view
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: lines
            delegate: QQC2.Label {
                required property string line
                width: ListView.view.width
                text: line
                color: Theme.textMuted
                font.family: "monospace"
                font.pointSize: Theme.smallFontSize
                wrapMode: Text.WrapAnywhere
            }
            QQC2.ScrollBar.vertical: QQC2.ScrollBar {}
        }
        QQC2.Label {
            Layout.fillWidth: true
            visible: sheet.detached && sheet.running
            text: qsTr("This keeps running if you close the app.")
            color: Theme.textMuted
            font.pointSize: Theme.smallFontSize
            wrapMode: Text.WordWrap
        }
        Button {
            Layout.alignment: Qt.AlignRight
            text: sheet.running ? qsTr("Hide") : qsTr("Close")
            enabled: !sheet.running || sheet.detached
            onClicked: sheet.close()
        }
    }
}
