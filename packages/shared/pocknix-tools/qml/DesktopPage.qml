import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import Pocknix.Ui

TabPage {
    id: page
    property var app
    title: qsTr("Desktop")
    icon: "monitor-symbolic"

    // pocknix-desktop-select list: name TAB label TAB active|""
    property var desktops: []
    property bool loaded: false

    function refresh() {
        listJob.start(["/usr/bin/pocknix-desktop-select", "list"])
    }
    // In game mode there is no desktop session to log out of: the pick applies next time.
    function pick(d) {
        if (Host.gamescope) {
            app.run(qsTr("Choosing %1").arg(d.label), ["/usr/bin/pocknix-desktop-select", d.name], {}, code => {
                refresh()
                if (code === 0)
                    app.notice(qsTr("%1 chosen").arg(d.label), qsTr("Desktop mode starts it from now on."))
            })
            return
        }
        app.ask({
            title: qsTr("Switch to %1 now?").arg(d.label),
            text: qsTr("This logs out of the current desktop, so open apps close: save your work first. Desktop mode starts %1 from now on.").arg(d.label),
            confirmText: qsTr("Switch now"),
            yes: () => app.run(qsTr("Switching to %1").arg(d.label),
                               ["/usr/bin/pocknix-desktop-select", d.name, "--now"], {}, () => refresh())
        })
    }

    Component.onCompleted: refresh()

    Job {
        id: listJob
        onFinished: {
            page.desktops = output.split("\n").filter(l => l).map(l => {
                const f = l.split("\t")
                return { name: f[0], label: f[1] || f[0], active: f[2] === "active" }
            })
            page.loaded = true
        }
    }

    QQC2.Label {
        Layout.fillWidth: true
        text: page.loaded && page.desktops.length === 0 ? qsTr("Desktop mode is not installed.")
                                                        : qsTr("The desktop that desktop mode starts.")
        color: Theme.textMuted
        wrapMode: Text.WordWrap
    }
    Repeater {
        model: page.desktops
        ActionRow {
            required property var modelData
            title: modelData.label
            StatusBadge {
                visible: modelData.active
                text: qsTr("In use")
                tone: "positive"
            }
            Button {
                visible: !modelData.active
                text: qsTr("Use")
                enabled: !page.app.logJobRunning
                onClicked: page.pick(modelData)
            }
        }
    }
    QQC2.Label {
        Layout.fillWidth: true
        text: qsTr("More desktops (Plasma Desktop, GNOME, COSMIC, Hyprland) install from the Pocknix Store, under Desktop mode.")
        color: Theme.textMuted
        wrapMode: Text.WordWrap
    }
}
