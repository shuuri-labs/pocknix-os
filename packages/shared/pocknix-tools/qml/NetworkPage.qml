import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import Pocknix.Ui

TabPage {
    id: page
    property var app
    title: qsTr("Network")

    // key=value status lines of pocknix-ssh / pocknix-share
    property var ssh: ({})
    property var share: ({})
    property string addresses: ""

    function parse(text) {
        const r = {}
        text.split("\n").forEach(l => {
            const i = l.indexOf("=")
            if (i > 0)
                r[l.slice(0, i)] = l.slice(i + 1)
        })
        return r
    }
    function refresh() {
        sshJob.start(["/usr/bin/pocknix-ssh", "status"])
        shareJob.start(["/usr/bin/pocknix-share", "status"])
        addrJob.start(["/usr/bin/ip", "-4", "-o", "addr", "show", "scope", "global"])
    }
    function toggle(cli, on, onDone) {
        app.run(on ? qsTr("Turning on") : qsTr("Turning off"), [cli, on ? "on" : "off"], { root: true }, code => {
            refresh()
            if (code === 0 && onDone)
                onDone()
        })
    }
    function sshOn() {
        app.ask({
            title: qsTr("Allow SSH logins?"),
            text: qsTr("Anyone on the same network can then log in with an account password, and Pocknix ships a well-known default one. If you have not changed it, do that first: run passwd in a terminal (then sudo passwd root).\n\nIt stays on, across reboots, until you turn it off here."),
            confirmText: qsTr("Turn on"),
            yes: () => toggle("/usr/bin/pocknix-ssh", true, () => app.notice(qsTr("SSH is on"),
                addresses ? qsTr("Log in as deck at %1.").arg(addresses) : qsTr("Log in as deck at this device's address.")))
        })
    }
    function shareOn() {
        if (share.installed !== "yes") {
            app.ask({
                title: qsTr("Install Samba?"),
                text: qsTr("File sharing needs Samba, which is not installed (7.4 MB download)."),
                confirmText: qsTr("Install"),
                yes: () => app.run(qsTr("Installing Samba"), ["/usr/bin/pocknix-share", "install"], { root: true },
                                   code => { refresh(); if (code === 0) shareOn() })
            })
            return
        }
        app.ask({
            title: qsTr("Share your home folder?"),
            text: qsTr("Anyone on the same network can then read and write every file in it: your games, saves and emulator settings, but also your Steam login and SSH keys. There is no password.\n\nOnly turn this on at home. It stays on, across reboots, until you turn it off here."),
            confirmText: qsTr("Turn on"),
            danger: true,
            yes: () => toggle("/usr/bin/pocknix-share", true, () => app.notice(qsTr("File sharing is on"),
                qsTr("On another computer, open smb://pocknix.local%1 and connect as Guest.")
                    .arg(addresses ? qsTr(" (or smb://%1)").arg(addresses.split(" ")[0]) : "")))
        })
    }

    Component.onCompleted: refresh()

    Job {
        id: sshJob
        onFinished: page.ssh = page.parse(output)
    }
    Job {
        id: shareJob
        onFinished: page.share = page.parse(output)
    }
    Job {
        id: addrJob
        onFinished: page.addresses = output.split("\n").map(l => l.trim().split(/\s+/)[3] || "")
            .filter(a => a).map(a => a.split("/")[0]).join(" ")
    }

    ActionRow {
        title: qsTr("Remote login (SSH)")
        description: page.ssh.state === "on" ? qsTr("On. Log in as deck%1.").arg(page.addresses ? qsTr(" at %1").arg(page.addresses) : "")
                                             : qsTr("Off")
        QQC2.Switch {
            checkable: false
            checked: page.ssh.state === "on"
            enabled: !page.app.logJobRunning && page.ssh.state !== undefined
            onClicked: checked ? page.toggle("/usr/bin/pocknix-ssh", false) : page.sshOn()
        }
    }
    ActionRow {
        title: qsTr("File sharing (SMB)")
        description: page.share.state === "on" ? qsTr("On: your home folder is shared on this network, without a password.")
            : page.share.installed === "yes" ? qsTr("Off") : qsTr("Off. Turning it on installs Samba first.")
        QQC2.Switch {
            checkable: false
            checked: page.share.state === "on"
            enabled: !page.app.logJobRunning && page.share.state !== undefined
            onClicked: checked ? page.toggle("/usr/bin/pocknix-share", false) : page.shareOn()
        }
    }
}
