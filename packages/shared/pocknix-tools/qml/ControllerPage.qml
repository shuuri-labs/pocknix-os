import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import Pocknix.Ui

TabPage {
    id: page
    property var app
    title: qsTr("Controller")
    icon: "input-gamepad-symbolic"

    readonly property string cli: "/usr/bin/pocknix-gamepad-calibration"
    // pocknix-gamepad-calibration status --json
    property var status: ({})
    property bool loaded: false
    property string loadError: ""
    // idle | starting | capture | review
    property string phase: "idle"
    // the last calibrate event, and how it ended (saved | discarded)
    property var step: ({})
    property string outcome: ""
    property var live: null
    property string liveError: ""
    // the CLI's "worked, but Steam may not see it yet" text from the job that just ran
    property string warning: ""

    function refresh() {
        statusJob.start([cli, "status", "--json"])
    }
    function startLive() {
        if (visible && status.available && phase === "idle" && !liveJob.running) {
            liveError = ""
            liveJob.start([cli, "live"], { root: true, input: true })
        }
    }
    function calibrate() {
        liveJob.closeInput()
        outcome = ""
        step = {}
        phase = "starting"
        calJob.start([cli, "calibrate"], { root: true, input: true })
    }
    // Closing stdin is the cancel: the CLI restores the old values and hands the pad back to Steam.
    function stop() {
        calJob.closeInput()
    }
    function reset() {
        app.ask({
            title: qsTr("Reset to defaults?"),
            text: qsTr("Your saved calibration is deleted and the sticks and triggers go back to their factory settings."),
            confirmText: qsTr("Reset"),
            danger: true,
            yes: () => resetJob.start([cli, "reset"], { root: true })
        })
    }

    function controlName(c) {
        switch (c) {
        case "left_stick": return qsTr("left stick")
        case "right_stick": return qsTr("right stick")
        case "left_trigger": return qsTr("left trigger")
        case "right_trigger": return qsTr("right trigger")
        default: return c || ""
        }
    }
    function directionName(d) {
        switch (d) {
        case "right": return qsTr("right")
        case "left": return qsTr("left")
        case "up": return qsTr("up")
        case "down": return qsTr("down")
        default: return d || ""
        }
    }
    function instruction(s) {
        const name = controlName(s.control)
        if (s.stage === "release")
            return qsTr("Let go of the %1 and keep your hands off it").arg(name)
        if (s.kind === "trigger")
            return qsTr("Press the %1 all the way in and hold it").arg(name)
        return qsTr("Push the %1 fully %2 and hold it there").arg(name).arg(directionName(s.direction))
    }

    Component.onCompleted: refresh()
    onVisibleChanged: {
        if (visible) {
            refresh()
        } else {
            liveJob.closeInput()
            stop()
        }
    }

    Job {
        id: statusJob
        onFinished: code => {
            page.loaded = true
            if (code !== 0) {
                page.loadError = error
                return
            }
            try {
                page.status = JSON.parse(output)
                page.loadError = ""
            } catch (e) {
                page.loadError = qsTr("pocknix-gamepad-calibration gave a reply Tools cannot read.")
                return
            }
            if (page.status.stale_intercept)
                recoverJob.start([page.cli, "recover"], { root: true })
            page.startLive()
        }
    }
    Job {
        id: recoverJob
        onEvent: data => {
            if (data.warning)
                page.warning = data.warning
        }
        onFinished: code => {
            const warning = page.warning
            page.warning = ""
            if (code === 0 && warning)
                page.app.notice(qsTr("Controller back to normal"), warning)
            else if (code === 0)
                page.app.toast(qsTr("Controller back to normal"),
                               qsTr("A calibration that stopped early had left it paused for Steam."))
            else
                page.app.notice(qsTr("Your controller may still be paused for Steam"),
                                qsTr("Restart the device to get it back.") + "\n\n" + error)
            page.refresh()
        }
    }
    Job {
        id: liveJob
        onEvent: data => {
            if (data.live)
                page.live = data.live
        }
        onFinished: code => {
            if (code === 0)
                page.startLive()
            else
                page.liveError = error
        }
    }
    Job {
        id: calJob
        onEvent: data => {
            if (data.live)
                page.live = data.live
            if (data.phase === "capture" || data.phase === "review") {
                page.phase = data.phase
                page.step = data
            } else if (data.phase) {
                page.outcome = data.phase
            }
            if (data.warning)
                page.warning = data.warning
        }
        onFinished: code => {
            page.phase = "idle"
            const warning = page.warning
            page.warning = ""
            if (code === 0 && warning)
                page.app.notice(page.outcome === "saved" ? qsTr("Calibration saved") : qsTr("Calibration discarded"), warning)
            else if (code === 0 && page.outcome === "saved")
                page.app.toast(qsTr("Calibration saved"), qsTr("The controller reconnects in a second. The calibration stays in use after a restart."))
            else if (code === 3)
                page.app.notice(qsTr("Calibration is already running"), qsTr("Finish it first, or restart the device."))
            else if (code !== 0)
                page.app.notice(qsTr("Calibration stopped"), error)
            page.refresh()
        }
    }
    // Without this the CLI takes the app for frozen and gives the pad back to Steam.
    Timer {
        interval: 1000
        repeat: true
        running: calJob.running
        onTriggered: calJob.send("ping")
    }
    Job {
        id: resetJob
        onEvent: data => {
            if (data.warning)
                page.warning = data.warning
        }
        onFinished: code => {
            const warning = page.warning
            page.warning = ""
            if (code === 0 && warning)
                page.app.notice(qsTr("Back to factory settings"), warning)
            else if (code === 0)
                page.app.toast(qsTr("Back to factory settings"), qsTr("The saved calibration is gone. The controller reconnects in a second."))
            else
                page.app.notice(qsTr("Could not reset the calibration"), error)
            page.refresh()
        }
    }

    // signed = a stick axis drawn from the centre; else a trigger from the left
    component Reading: RowLayout {
        id: reading
        property string label
        property real value: 0
        property bool signed: false
        Layout.fillWidth: true
        spacing: Theme.spacing

        QQC2.Label {
            text: reading.label
            Layout.preferredWidth: Theme.unit * 7
        }
        Rectangle {
            id: track
            Layout.fillWidth: true
            implicitHeight: Theme.smallSpacing * 3
            radius: height / 2
            color: Theme.surfaceHigh
            Rectangle {
                height: parent.height
                radius: parent.radius
                color: Theme.accent
                readonly property real v: Math.max(reading.signed ? -1 : 0, Math.min(1, reading.value))
                x: reading.signed ? track.width / 2 + Math.min(0, v) * track.width / 2 : 0
                width: reading.signed ? Math.abs(v) * track.width / 2 : v * track.width
            }
            Rectangle {
                visible: reading.signed
                x: track.width / 2 - width / 2
                width: 2
                height: parent.height
                color: Theme.textMuted
            }
        }
        QQC2.Label {
            text: reading.signed ? Math.round(reading.value * 100) : qsTr("%1%").arg(Math.round(reading.value * 100))
            horizontalAlignment: Text.AlignRight
            Layout.preferredWidth: Theme.unit * 2.5
        }
    }

    QQC2.Label {
        text: qsTr("Sticks and triggers")
        font.bold: true
        font.pointSize: Theme.titleFontSize
    }
    LoadState {
        loading: !page.loaded
        error: page.loadError
        onRetry: {
            page.loaded = false
            page.loadError = ""
            page.refresh()
        }
    }
    ActionRow {
        visible: page.loaded && page.loadError === "" && !page.status.available
        title: qsTr("This controller can't be calibrated")
        description: qsTr("Its driver has no calibration settings, so there is nothing to adjust on this device.")
    }

    ActionRow {
        visible: page.status.available === true && page.phase === "idle"
        title: page.status.saved ? qsTr("A saved calibration is in use") : qsTr("Using the factory settings")
        description: page.status.running ? qsTr("A calibration is already running.")
            : page.status.saved && page.status.defaults_recorded === false
            ? qsTr("Restart the device once before resetting: the factory settings are recorded at startup.")
            : qsTr("Calibrating walks each stick and trigger to its edge and back. Your controller is paused for Steam while it runs, so cancel on the screen.")
        Button {
            text: qsTr("Calibrate")
            kind: Button.Primary
            enabled: !calJob.running && !resetJob.running && !recoverJob.running && !page.status.running
            onClicked: page.calibrate()
        }
        Button {
            text: qsTr("Reset to Defaults")
            kind: Button.Danger
            enabled: page.status.saved === true && page.status.defaults_recorded !== false
                && !calJob.running && !resetJob.running && !recoverJob.running && !page.status.running
            onClicked: page.reset()
        }
    }

    ColumnLayout {
        visible: page.phase === "starting" || page.phase === "capture"
        Layout.fillWidth: true
        spacing: Theme.spacing

        QQC2.Label {
            Layout.fillWidth: true
            text: page.phase === "starting" ? qsTr("Getting ready…")
                : qsTr("Step %1 of %2 · your controller is paused for Steam").arg(page.step.step).arg(page.step.steps)
            color: Theme.textMuted
            wrapMode: Text.WordWrap
        }
        QQC2.Label {
            Layout.fillWidth: true
            visible: page.phase === "capture"
            text: page.phase === "capture" ? page.instruction(page.step) : ""
            font.pointSize: Theme.titleFontSize * 1.3
            wrapMode: Text.WordWrap
        }
        QQC2.ProgressBar {
            Layout.fillWidth: true
            visible: page.phase === "capture"
            from: 0
            to: 1
            value: page.step.progress || 0
        }
    }

    QQC2.Label {
        Layout.fillWidth: true
        visible: page.phase === "review"
        text: qsTr("Calibration applied. Check the sticks and triggers below: a full push should read 100 at the edge and 0 at rest. Save keeps it after a restart.")
        wrapMode: Text.WordWrap
    }

    QQC2.Label {
        Layout.fillWidth: true
        visible: page.liveError !== ""
        text: qsTr("Live readings stopped: %1").arg(page.liveError)
        color: Theme.negative
        wrapMode: Text.WordWrap
    }
    ColumnLayout {
        visible: page.status.available === true && page.live !== null
        Layout.fillWidth: true
        Layout.topMargin: Theme.smallSpacing
        spacing: Theme.smallSpacing
        Reading { label: qsTr("Left stick X"); value: page.live ? page.live.lx : 0; signed: true }
        Reading { label: qsTr("Left stick Y"); value: page.live ? page.live.ly : 0; signed: true }
        Reading { label: qsTr("Right stick X"); value: page.live ? page.live.rx : 0; signed: true }
        Reading { label: qsTr("Right stick Y"); value: page.live ? page.live.ry : 0; signed: true }
        Reading { label: qsTr("Left trigger"); value: page.live ? page.live.lt : 0 }
        Reading { label: qsTr("Right trigger"); value: page.live ? page.live.rt : 0 }
    }

    RowLayout {
        visible: page.phase === "starting" || page.phase === "capture"
        Layout.fillWidth: true
        Layout.topMargin: Theme.spacing
        Button {
            Layout.fillWidth: true
            text: qsTr("Cancel")
            onClicked: page.stop()
        }
    }
    RowLayout {
        visible: page.phase === "review"
        Layout.fillWidth: true
        Layout.topMargin: Theme.spacing
        spacing: Theme.spacing
        Button {
            text: qsTr("Save")
            kind: Button.Primary
            onClicked: calJob.send("save")
        }
        Button {
            text: qsTr("Discard")
            onClicked: page.stop()
        }
    }
}
