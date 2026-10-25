import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import Pocknix.Ui

TabPage {
    id: page
    property var app
    title: qsTr("System")
    icon: "system-software-update-symbolic"

    property var base: ({})
    // null = not checked yet; else [[name, from, to], ...]
    property var updates: null
    property var snapshots: []
    property var internal: []
    property bool showAll: false
    readonly property bool busy: app.logJobRunning || checkJob.running

    // pocknix-rollback --list: ID, date, time, OK, KERNEL (yes or -), then the update's targets
    function parseSnapshots(text) {
        return text.split("\n").slice(1).filter(l => /^\d/.test(l)).map(l => {
            const f = l.trim().split(/\s+/)
            const d = f[1].split("-"), t = f[2].split(":")
            return { id: f[0], when: new Date(d[2], d[1] - 1, d[0], t[0], t[1]), ok: f[3] === "yes",
                     kernel: f[4] === "yes", targets: f.slice(5).join(" ") }
        }).reverse()
    }
    function refresh() {
        baseJob.start(["/usr/bin/pocknix-base", "status", "--json"])
        snapJob.start(["/usr/bin/pocknix-rollback", "--list"])
    }
    function update() {
        app.run(qsTr("Updating"), ["/usr/bin/pocknix-update", "--gui"], { root: true, detached: true }, code => {
            refresh()
            if (code !== 0)
                return
            updates = []
            kernelJob.start(["/usr/bin/test", "-e", "/run/pocknix/reboot-required"])
        })
    }
    function rollback(s, flag) {
        app.ask({
            title: qsTr("Roll back to %1?").arg(s.when.toLocaleString(Qt.locale(), "d MMM, HH:mm")),
            text: qsTr("Everything that update changed is undone, including the kernel if it was part of it. Games, saves, settings and logs are kept.")
                + "\n" + (flag ? qsTr("The internal install boots into it the next time you start from internal storage.")
                               : qsTr("Restart right after.")),
            confirmText: qsTr("Roll back"),
            hold: true,
            danger: true,
            yes: () => app.run(qsTr("Rolling back"),
                               ["/usr/bin/pocknix-rollback"].concat(flag ? [flag] : []).concat(["--to", s.id, "--yes"]),
                               { root: true }, code => {
                refresh()
                if (code === 0 && !flag)
                    app.askReboot(qsTr("Rolled back"), qsTr("A restart completes the rollback."))
                else if (code === 0)
                    app.notice(qsTr("Internal install rolled back"), qsTr("It starts in that state the next time you boot from internal storage."))
            })
        })
    }

    Component.onCompleted: {
        refresh()
        internalJob.start(["/usr/bin/pocknix-rollback", "--internal", "--list"], { root: true })
        updateState.start([app.jobRunner, "status", "update"])
    }

    // The snapshot hook marks an update that changed the kernel, Check run first or not.
    Job {
        id: kernelJob
        onFinished: code => {
            if (code === 0)
                page.app.askReboot(qsTr("Updated"), qsTr("The update includes a new kernel. Restart to use it."))
            else
                page.app.notice(qsTr("Updated"), qsTr("Pocknix is up to date."))
        }
    }
    Job {
        id: baseJob
        onFinished: code => {
            if (code === 0)
                page.base = JSON.parse(output)
        }
    }
    Job {
        id: snapJob
        onFinished: code => page.snapshots = code === 0 ? page.parseSnapshots(output) : []
    }
    // Fails on a device booted from internal storage or without an internal install: no section.
    Job {
        id: internalJob
        onFinished: code => page.internal = code === 0 ? page.parseSnapshots(output) : []
    }
    // Reopened while an update runs: show it again.
    Job {
        id: updateState
        onFinished: code => {
            if (output.trim() === "running")
                page.app.run(qsTr("Finishing the update"), ["/usr/bin/pocknix-update", "--follow"],
                             { detached: true }, () => page.refresh())
        }
    }
    Job {
        id: checkJob
        onFinished: code => {
            if (code === 0)
                page.updates = JSON.parse(output).updates
            else
                page.app.notice(qsTr("Could not check for updates"), error)
        }
    }

    ActionRow {
        title: page.base.version ? qsTr("Pocknix %1").arg(page.base.version) : qsTr("Pocknix")
        description: page.base.mode === "locked" ? qsTr("Tested package base %1").arg(page.base.snapshot)
            : page.base.mode === "rolling" ? qsTr("Rolling: live Arch Linux ARM packages, unsupported")
            : ""
        StatusBadge {
            text: page.base.mode === "rolling" ? qsTr("Rolling") : qsTr("Locked")
            tone: page.base.mode === "rolling" ? "warning" : "positive"
            visible: !!page.base.mode
        }
    }
    ActionRow {
        visible: !!page.base.blocked
        title: qsTr("Base update blocked")
        description: qsTr("Remove %1, then return to locked mode.").arg(page.base.blocked || "")
        StatusBadge { text: qsTr("Blocked"); tone: "negative" }
    }

    QQC2.Label {
        Layout.topMargin: Theme.spacing
        text: qsTr("Updates")
        font.bold: true
        font.pointSize: Theme.titleFontSize
    }
    ActionRow {
        title: page.updates === null ? qsTr("Not checked yet")
            : page.updates.length === 0 ? qsTr("Everything is up to date")
            : qsTr("%n update(s) available", "", page.updates.length)
        description: page.updates && page.updates.length > 0
            ? page.updates.slice(0, 6).map(u => u[0]).join(", ") + (page.updates.length > 6 ? " …" : "")
            : qsTr("A snapshot is taken before every update, so you can roll it back.")
        busy: checkJob.running

        QQC2.Button {
            implicitHeight: Theme.touchTarget
            text: qsTr("Check")
            enabled: !page.busy
            onClicked: checkJob.start(["/usr/bin/pocknix-update", "--check"], { root: true })
        }
        QQC2.Button {
            implicitHeight: Theme.touchTarget
            text: qsTr("Update now")
            enabled: !page.busy
            palette.button: page.updates && page.updates.length > 0 ? Theme.accent : Theme.surfaceHigh
            palette.buttonText: page.updates && page.updates.length > 0 ? Theme.accentText : Theme.text
            onClicked: page.update()
        }
    }

    QQC2.Label {
        Layout.topMargin: Theme.spacing
        text: qsTr("Roll back an update")
        font.bold: true
        font.pointSize: Theme.titleFontSize
    }
    QQC2.Label {
        Layout.fillWidth: true
        text: page.snapshots.length > 0
            ? qsTr("Each one is the system as it was before that update. Newest first.")
            : qsTr("No snapshots yet: one is taken before every update.")
        color: Theme.textMuted
        wrapMode: Text.WordWrap
    }
    Repeater {
        model: page.showAll ? page.snapshots : page.snapshots.slice(0, 5)
        ActionRow {
            required property var modelData
            title: modelData.when.toLocaleString(Qt.locale(), "d MMM yyyy, HH:mm")
            description: modelData.targets + (modelData.kernel ? " · " + qsTr("includes the kernel") : "")
            QQC2.Button {
                implicitHeight: Theme.touchTarget
                text: qsTr("Roll back")
                enabled: !page.busy
                onClicked: page.rollback(modelData, "")
            }
        }
    }
    QQC2.Button {
        visible: page.snapshots.length > 5
        implicitHeight: Theme.touchTarget
        text: page.showAll ? qsTr("Show fewer") : qsTr("Show all %1").arg(page.snapshots.length)
        onClicked: page.showAll = !page.showAll
    }

    QQC2.Label {
        visible: page.internal.length > 0
        Layout.topMargin: Theme.spacing
        text: qsTr("Internal install")
        font.bold: true
        font.pointSize: Theme.titleFontSize
    }
    Repeater {
        model: page.internal.slice(0, 5)
        ActionRow {
            required property var modelData
            title: modelData.when.toLocaleString(Qt.locale(), "d MMM yyyy, HH:mm")
            description: modelData.targets + (modelData.kernel ? " · " + qsTr("includes the kernel") : "")
            QQC2.Button {
                implicitHeight: Theme.touchTarget
                text: qsTr("Roll back")
                enabled: !page.busy
                onClicked: page.rollback(modelData, "--internal")
            }
        }
    }
}
