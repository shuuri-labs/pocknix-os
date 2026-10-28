import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Pocknix.Ui

// One entry's actions. The Steam tile state is read when the sheet opens, never for the whole
// list: every pocknix-tiles call is a round trip into Steam.
Sheet {
    id: sheet
    property var entry: null
    property bool locked: false
    // "" (no tile) | loading | enabled | disabled | busy | no-account | error
    property string tileState: ""
    property string tileError: ""
    signal install(string id)
    signal remove(string id)
    signal reset(string id)


    onOpened: {
        tileError = ""
        if (entry && entry.tile) {
            tileState = "loading"
            tileJob.run("status")
        } else {
            tileState = ""
        }
    }

    Job {
        id: tileJob
        property string op

        function run(o) {
            op = o
            start(["/usr/bin/pocknix-tiles", o, sheet.entry.tile])
        }

        onFinished: code => {
            if (code === 0) {
                sheet.tileState = op === "status" ? output.trim()
                    : op === "enable" ? "enabled" : "disabled"
                return
            }
            sheet.tileState = code === 3 ? "busy" : code === 4 ? "no-account" : "error"
            sheet.tileError = error
        }
    }

    contentItem: ColumnLayout {
        spacing: Theme.spacing

        RowLayout {
            spacing: Theme.spacing
            Kirigami.Icon {
                source: sheet.entry ? sheet.entry.icon : ""
                implicitWidth: Theme.iconSize * 1.5
                implicitHeight: Theme.iconSize * 1.5
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                QQC2.Label {
                    Layout.fillWidth: true
                    text: sheet.entry ? sheet.entry.name : ""
                    font.bold: true
                    font.pointSize: Theme.titleFontSize
                    elide: Text.ElideRight
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    text: sheet.entry ? sheet.entry.description : ""
                    color: Theme.textMuted
                    wrapMode: Text.WordWrap
                }
            }
            StatusBadge {
                visible: sheet.entry && sheet.entry.installed
                text: qsTr("Installed")
                tone: "positive"
            }
        }

        ActionRow {
            visible: sheet.tileState !== ""
            title: qsTr("Tile in the Steam library")
            description: sheet.tileState === "busy"
                ? qsTr("Steam cannot change tiles right now. Wait for it to finish starting, or exit Steam, then try again.")
                : sheet.tileState === "no-account" ? qsTr("Sign in to Steam first.")
                : sheet.tileState === "error" ? sheet.tileError : ""
            busy: tileJob.running

            QQC2.Switch {
                // The state comes back from Steam: a tap asks, the answer flips the switch.
                checkable: false
                checked: sheet.tileState === "enabled"
                enabled: !tileJob.running && (sheet.tileState === "enabled" || sheet.tileState === "disabled")
                onClicked: tileJob.run(checked ? "disable" : "enable")
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignRight
            spacing: Theme.spacing

            QQC2.Button {
                visible: sheet.entry && sheet.entry.reset
                enabled: !sheet.locked
                implicitHeight: Theme.touchTarget
                text: qsTr("Restore default settings")
                onClicked: {
                    sheet.close()
                    sheet.reset(sheet.entry.id)
                }
            }
            QQC2.Button {
                visible: sheet.entry && sheet.entry.installed
                enabled: !sheet.locked
                implicitHeight: Theme.touchTarget
                text: qsTr("Remove")
                palette.button: Theme.negative
                palette.buttonText: Theme.accentText
                onClicked: {
                    sheet.close()
                    sheet.remove(sheet.entry.id)
                }
            }
            QQC2.Button {
                visible: sheet.entry && !sheet.entry.installed
                enabled: !sheet.locked
                implicitHeight: Theme.touchTarget
                text: qsTr("Install")
                palette.button: Theme.accent
                palette.buttonText: Theme.accentText
                onClicked: {
                    sheet.close()
                    sheet.install(sheet.entry.id)
                }
            }
            QQC2.Button {
                implicitHeight: Theme.touchTarget
                text: qsTr("Close")
                onClicked: sheet.close()
            }
        }
    }
}
