import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import Pocknix.Ui

TabPage {
    id: page
    property var app
    title: qsTr("Advanced")
    icon: "configure-symbolic"

    readonly property string runner: "/usr/bin/pocknix-tools-run"
    // key=value probes: pocknix-update-abl --status, pocknix-install-internal --detect
    property var abl: ({})
    readonly property int androidDefaultGib: 32
    property var internal: ({})
    readonly property string baseMode: app.base.mode || ""
    // Android's share of the internal disk, in whole GB within what the installer allows
    property int androidGib: 0
    readonly property int minGib: parseInt(internal.android_min_gib) || 0
    readonly property int maxGib: parseInt(internal.android_max_gib) || 0

    function refresh() {
        ablJob.start(["/usr/bin/pocknix-update-abl", "--status"], { root: true })
        detectJob.start(["/usr/bin/pocknix-install-internal", "--detect"], { root: true })
        app.refreshBase()
    }
    function step(title, args, done) {
        app.run(title, [runner].concat(args), { root: true, detached: true }, code => {
            refresh()
            if (code === 0 && done)
                done()
        })
    }
    function askPowerOff(title, text) {
        app.ask({ title: title, text: text, confirmText: qsTr("Power off"),
                  yes: () => powerJob.start(["/usr/bin/systemctl", "poweroff"]) })
    }

    Component.onCompleted: {
        refresh()
        toolsState.start([app.jobRunner, "status", "tools"])
    }

    Job {
        id: ablJob
        onFinished: code => page.abl = code === 0 ? Util.kv(output) : ({})
    }
    Job {
        id: detectJob
        onFinished: code => {
            page.internal = code === 0 ? Util.kv(output) : ({})
            if (page.internal.mode === "fresh") {
                const lo = parseInt(page.internal.android_min_gib), hi = parseInt(page.internal.android_max_gib)
                page.androidGib = hi >= page.androidDefaultGib ? Math.max(page.androidDefaultGib, lo) : lo
            }
        }
    }
    // Reopened while a step runs: show it again.
    Job {
        id: toolsState
        onFinished: code => {
            if (output.trim() === "running")
                page.app.run(qsTr("Finishing the last step"), [page.runner, "follow"], { detached: true },
                             () => page.refresh())
        }
    }
    Job {
        id: powerJob
        onFinished: code => {
            if (code !== 0)
                page.app.notice(qsTr("Power off failed"), error)
        }
    }

    QQC2.Label {
        Layout.fillWidth: true
        text: qsTr("These change the bootloader, the internal storage or where packages come from. Each asks you to press and hold before it starts.")
        color: Theme.textMuted
        wrapMode: Text.WordWrap
    }

    QQC2.Label {
        visible: ablRow.visible
        Layout.topMargin: Theme.spacing
        text: qsTr("Bootloader")
        font.bold: true
        font.pointSize: Theme.titleFontSize
    }
    ActionRow {
        id: ablRow
        visible: ["uptodate", "differs", "mixed", "gptrepair"].includes(page.abl.state)
        title: qsTr("Bootloader (ABL)")
        description: page.abl.state === "uptodate" ? qsTr("Up to date (%1)").arg(page.abl.shipped_version)
            : page.abl.state === "gptrepair" ? qsTr("The partition table needs a repair before %1 can be installed.").arg(page.abl.shipped_version)
            : qsTr("Version %1 is available.").arg(page.abl.shipped_version)
        Button {
            visible: page.abl.state !== "uptodate"
            enabled: !page.app.logJobRunning
            text: page.abl.state === "gptrepair" ? qsTr("Repair and install") : qsTr("Install")
            kind: Button.Danger
            onClicked: page.app.ask({
                title: page.abl.state === "gptrepair" ? qsTr("Repair the partition table and install the bootloader?")
                                                      : qsTr("Install bootloader %1?").arg(page.abl.shipped_version),
                text: (page.abl.state === "gptrepair"
                       ? qsTr("Many Retroid units ship with a damaged partition table. Only a single 4 KB header is rewritten, from this disk's own backup copy; no partition contents are touched and the original is kept.\n\n")
                       : "")
                    + qsTr("This rewrites both bootloader slots on internal storage. If it is interrupted the device will not boot and needs a PC to recover. Keep it plugged in. The current bootloader is backed up first, and each slot is verified after writing."),
                confirmText: qsTr("Install"),
                hold: true,
                danger: true,
                yes: () => page.step(qsTr("Installing the bootloader"), ["abl"],
                                     () => page.app.toast(qsTr("Bootloader installed"), qsTr("It is used from the next start.")))
            })
        }
    }

    QQC2.Label {
        visible: !!page.internal.mode
        Layout.topMargin: Theme.spacing
        text: qsTr("Internal storage")
        font.bold: true
        font.pointSize: Theme.titleFontSize
    }
    ActionRow {
        visible: page.internal.mode === "internal"
        title: qsTr("Pocknix is running from internal storage")
        description: qsTr("To start from the SD card, or to remove Pocknix from internal storage: power off, then hold Volume - while powering on to open the ROCKNIX boot menu. Switch boot source picks SD card or internal; Uninstall CFW removes Pocknix and gives Android its storage back (Android then factory-resets). To start Android once, hold Volume + while powering on.")
    }
    ActionRow {
        visible: ["toosmall", "nofit", "foreign"].includes(page.internal.mode)
        title: qsTr("Cannot install to internal storage")
        description: page.internal.mode === "toosmall"
            ? qsTr("Pocknix needs about %1 GB and Android's data partition is only %2 GB.").arg(page.internal.needed_gib).arg(page.internal.android_current_gib)
            : page.internal.mode === "nofit"
            ? qsTr("The SD card holds %1 GB of Pocknix data, but internal storage has room for at most %2 GB. Free at least %3 GB on the SD card (uninstall games, move ROMs), then try again.")
                .arg(page.internal.sd_used_gib).arg(page.internal.pocknix_max_gib).arg(page.internal.free_gib)
            : qsTr("Internal storage holds a Linux install this tool did not create (for example ROCKNIX). Remove it first: boot menu, Uninstall CFW.")
    }
    ActionRow {
        visible: page.internal.mode === "fresh"
        title: qsTr("Install Pocknix to internal storage")
        description: qsTr("Next to Android, which keeps %1 GB. Pocknix gets %2 GB (%3 GB to copy from this SD card). Android is factory-reset: its apps and their data are lost.")
            .arg(page.androidGib).arg(parseInt(page.internal.android_current_gib) - page.androidGib).arg(page.internal.sd_used_gib)
        Button {
            enabled: !page.app.logJobRunning
            text: qsTr("Install")
            kind: Button.Danger
            onClicked: page.app.ask({
                title: qsTr("Install Pocknix to internal storage?"),
                text: qsTr("Android keeps %1 GB, Pocknix gets %2 GB. This factory-resets Android: installed Android apps and their data are lost (Android itself stays). The SD card is not touched, and nothing before the Android data partition is changed, so the bootloader stays safe. Do not power off until it finishes.")
                    .arg(page.androidGib).arg(parseInt(page.internal.android_current_gib) - page.androidGib),
                confirmText: qsTr("Install"),
                hold: true,
                danger: true,
                yes: () => page.step(qsTr("Installing to internal storage"), ["install-internal", String(page.androidGib)],
                    () => page.askPowerOff(qsTr("Installed"), qsTr("Power off and remove the SD card, then hold Volume - while powering on to open the ROCKNIX boot menu and set Switch boot source to Internal.")))
            })
        }
    }
    RowLayout {
        visible: page.internal.mode === "fresh"
        Layout.fillWidth: true
        spacing: Theme.spacing
        QQC2.Label {
            text: qsTr("Android keeps")
            color: Theme.textMuted
        }
        QQC2.Slider {
            id: sizeSlider
            Layout.fillWidth: true
            implicitHeight: Theme.touchTarget
            from: page.minGib
            to: page.maxGib
            stepSize: 1
            snapMode: QQC2.Slider.SnapAlways
            value: page.androidGib
            onMoved: page.androidGib = Math.round(value)
        }
        QQC2.SpinBox {
            implicitHeight: Theme.touchTarget
            from: page.minGib
            to: page.maxGib
            editable: true
            value: page.androidGib
            textFromValue: (v, locale) => qsTr("%1 GB").arg(v)
            valueFromText: (text, locale) => parseInt(text) || page.minGib
            validator: RegularExpressionValidator { regularExpression: /\d{1,4}( ?GB)?/ }
            onValueModified: page.androidGib = value
        }
    }
    ActionRow {
        visible: page.internal.mode === "occupied"
        title: qsTr("Pocknix is installed on internal storage")
        description: qsTr("Android: %1 GB, Pocknix: %2 GB. To reinstall, remove it, then install again.")
            .arg(page.internal.android_gib).arg(page.internal.pocknix_gib)
        Button {
            enabled: !page.app.logJobRunning
            text: qsTr("Remove")
            kind: Button.Danger
            onClicked: page.app.ask({
                title: qsTr("Remove Pocknix from internal storage?"),
                text: qsTr("This erases the internal Pocknix and gives all internal storage back to Android, which factory-resets on its next start. Do not power off until it finishes."),
                confirmText: qsTr("Remove"),
                hold: true,
                danger: true,
                yes: () => page.step(qsTr("Removing from internal storage"), ["uninstall-internal"],
                    () => page.app.notice(qsTr("Removed"), qsTr("Android has the full internal storage again. To start Android, power off and remove the SD card.")))
            })
        }
    }

    QQC2.Label {
        visible: !!page.baseMode
        Layout.topMargin: Theme.spacing
        text: qsTr("Package base")
        font.bold: true
        font.pointSize: Theme.titleFontSize
    }
    ActionRow {
        visible: page.baseMode === "locked" || page.baseMode === "rolling"
        title: page.baseMode === "rolling" ? qsTr("Rolling (unsupported)") : qsTr("Locked (recommended)")
        description: page.baseMode === "rolling"
            ? qsTr("Packages come from live Arch Linux ARM. Return to the tested Pocknix base: every base package converges back to it, downgrades included.")
            : qsTr("Packages come from the tested Pocknix base and update together.")
        Button {
            enabled: !page.app.logJobRunning
            text: page.baseMode === "rolling" ? qsTr("Return to locked") : qsTr("Switch to rolling")
            onClicked: page.baseMode === "rolling"
                ? page.app.ask({
                    title: qsTr("Return to the locked base?"),
                    text: qsTr("Every base package converges back to the Pocknix snapshot, downgrades included. Software installed while rolling may block this; the log names it if so."),
                    confirmText: qsTr("Return to locked"),
                    yes: () => page.step(qsTr("Returning to the locked base"), ["locked"])
                })
                : page.app.ask({
                    title: qsTr("Switch to rolling mode?"),
                    text: qsTr("Rolling mode is NOT recommended. It switches this device from the tested Pocknix package base to live Arch Linux ARM. Any upstream update can then break the Steam session, graphics or boot until the next Pocknix release. It is for people who manage packages with pacman themselves, and it is unsupported. Every update is still snapshotted, and Return to locked comes back."),
                    confirmText: qsTr("Switch to rolling"),
                    hold: true,
                    danger: true,
                    yes: () => page.step(qsTr("Switching to rolling"), ["rolling"])
                })
        }
    }
}
