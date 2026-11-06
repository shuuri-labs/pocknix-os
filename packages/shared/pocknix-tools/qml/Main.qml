import QtQuick
import Pocknix.Ui

AppWindow {
    id: app
    title: qsTr("Pocknix Tools")

    readonly property string jobRunner: "/usr/lib/pocknix-ui/pocknix-job"
    readonly property bool logJobRunning: logJob.running
    // pocknix-base status --json, read once for System and Advanced
    property var base: ({})
    property bool baseLoaded: false
    property string baseError: ""

    // A read in flight began after whatever change asked for this one, so it is fresh enough.
    function refreshBase() {
        if (!baseJob.running)
            baseJob.start(["/usr/bin/pocknix-base", "status", "--json"])
    }


    // A change with a log: `done(code)` runs when it ends. A detached one (pacman under
    // pocknix-job) keeps running when the sheet or the app closes.
    function run(title, argv, options, done) {
        // A second start would queue behind the first while the sheet shows the new title.
        if (logJob.running)
            return
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
    EmulationPage {
        app: app
    }
    DesktopPage {
        app: app
    }
    AdvancedPage {
        app: app
    }


    LogSheet {
        id: log
        job: logJob
    }
    Job {
        id: baseJob
        onFinished: code => {
            app.baseLoaded = true
            if (code !== 0) {
                app.baseError = error
                return
            }
            try {
                app.base = JSON.parse(output)
                app.baseError = ""
            } catch (e) {
                app.baseError = qsTr("pocknix-base gave a reply Tools cannot read.")
            }
        }
    }
}
