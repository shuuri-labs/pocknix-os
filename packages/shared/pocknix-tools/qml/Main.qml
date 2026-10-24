import QtQuick
import Pocknix.Ui

AppWindow {
    id: app
    title: qsTr("Pocknix Tools")

    readonly property string jobRunner: "/usr/lib/pocknix-ui/pocknix-job"
    property var pending: null
    readonly property bool logJobRunning: logJob.running

    function ask(o) {
        askSheet.title = o.title
        askSheet.text = o.text || ""
        askSheet.confirmText = o.confirmText || qsTr("OK")
        askSheet.cancelText = o.notice ? "" : qsTr("Cancel")
        askSheet.hold = !!o.hold
        askSheet.danger = !!o.danger
        pending = o.yes || null
        askSheet.open()
    }
    function notice(title, text) {
        ask({ title: title, text: text, notice: true })
    }

    // A change with a log: `done(code)` runs when it ends. A detached one (pacman under
    // pocknix-job) keeps running when the sheet or the app closes.
    function run(title, argv, options, done) {
        log.title = title
        log.detached = !!(options && options.detached)
        logJob.done = done || null
        logJob.start(argv, options || {})
        log.open()
    }
    function reboot() {
        rebootJob.start(["/usr/bin/systemctl", "reboot"])
    }
    function askReboot(title, text) {
        ask({ title: title, text: text, confirmText: qsTr("Restart now"), yes: reboot })
    }

    Job {
        id: logJob
        property var done: null
        onFinished: code => {
            if (code === 0)
                log.close()
            const f = done
            done = null
            if (f)
                f(code)
        }
    }

    Job {
        id: rebootJob
        onFinished: code => {
            if (code !== 0)
                app.notice(qsTr("Restart failed"), error)
        }
    }

    SystemPage {
        app: app
    }
    NetworkPage {
        app: app
    }
    DesktopPage {
        app: app
    }
    AdvancedPage {
        app: app
    }

    ConfirmSheet {
        id: askSheet
        onAccepted: {
            const f = app.pending
            app.pending = null
            if (f)
                f()
        }
    }

    LogSheet {
        id: log
        job: logJob
    }
}
