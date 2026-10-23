import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import Pocknix.Ui

AppWindow {
    id: app
    title: qsTr("Pocknix Store")

    readonly property string cli: "/usr/bin/pocknix-store"
    property var store: ({ mode: "none", job: "none", sections: [], entries: [] })
    property bool loaded: false
    property bool attached: false
    // what the running store job works on: its tiles show busy
    property var acting: []
    property string actingKind: ""
    // ids whose Steam tiles to offer once the status after an install is in
    property var offerTiles: []
    property var pending: null

    function refresh() {
        statusJob.start([cli, "status", "--json"])
    }
    function entry(id) {
        return store.entries.find(e => e.id === id)
    }
    function inSection(section) {
        return store.entries.filter(e => e.section === section)
    }
    function installedTiles(section) {
        return inSection(section).filter(e => e.installed && e.tile)
    }

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

    function act(kind, ids, title) {
        acting = ids
        actingKind = kind
        log.title = title
        actionJob.start([cli, kind].concat(ids), { root: true })
        log.open()
    }

    function install(id) {
        const e = entry(id)
        ask({
            title: qsTr("Install %1?").arg(e.name),
            text: qsTr("It is downloaded with a full system update, so this can take a while."),
            confirmText: qsTr("Install"),
            yes: () => act("install", [id], qsTr("Installing %1").arg(e.name))
        })
    }
    function remove(id) {
        const e = entry(id)
        const emulation = e.section === "emulation"
        ask({
            title: qsTr("Remove %1?").arg(e.name),
            text: (emulation && store.mode === "all" ? qsTr("The other emulators stay installed. ") : "")
                + (emulation ? qsTr("Close it first. Its Steam tile goes with it; your ROMs, saves and settings are kept.")
                             : qsTr("It can be installed again at any time.")),
            confirmText: qsTr("Remove"),
            danger: true,
            yes: () => act("remove", [id], qsTr("Removing %1").arg(e.name))
        })
    }
    function reset(id) {
        const e = entry(id)
        ask({
            title: qsTr("Restore default settings for %1?").arg(e.name),
            text: qsTr("The current settings file is kept next to the new one as a .bak copy. Games, saves and controller profiles are not touched."),
            confirmText: qsTr("Restore"),
            yes: () => {
                resetJob.name = e.name
                resetJob.start(["/usr/bin/pocknix-roms-init", "--reset", id])
            }
        })
    }
    function addTiles(list) {
        tilesJob.count = list.length
        tilesJob.start(["/usr/bin/pocknix-tiles", "enable"].concat(list.map(e => e.tile)))
    }
    function tileFailure(code, error) {
        if (code === 3)
            return qsTr("Steam cannot take new tiles right now. Wait for it to finish starting, or exit Steam, then try again.")
        if (code === 4)
            return qsTr("Steam has no account on this device yet. Sign in to Steam, then try again.")
        return error
    }

    Component.onCompleted: refresh()

    Job {
        id: statusJob
        onFinished: code => {
            if (code === 0) {
                try {
                    app.store = JSON.parse(output)
                } catch (e) {
                    console.warn("pocknix-store status:", e)
                }
            }
            app.loaded = true
            // Reopened while a change runs: show it again instead of a store that looks idle.
            if (!app.attached) {
                app.attached = true
                if (app.store.job === "running") {
                    log.title = qsTr("Finishing the last change")
                    actionJob.start([app.cli, "follow"])
                    log.open()
                }
            }
            const offer = app.store.entries.filter(e => app.offerTiles.includes(e.id) && e.installed && e.tile)
            app.offerTiles = []
            if (offer.length > 0)
                app.ask({
                    title: offer.length === 1 ? qsTr("Add %1 to Steam?").arg(offer[0].name)
                                              : qsTr("Add %1 tiles to Steam?").arg(offer.length),
                    text: qsTr("A tile in your Steam library starts it in game mode."),
                    confirmText: qsTr("Add"),
                    yes: () => app.addTiles(offer)
                })
        }
    }

    Job {
        id: actionJob
        onFinished: code => {
            if (code === 0) {
                log.close()
                if (app.actingKind === "install")
                    app.offerTiles = app.acting
                else if (app.actingKind === "install-all")
                    app.offerTiles = app.store.entries.filter(e => e.section === "emulation").map(e => e.id)
            }
            app.acting = []
            app.actingKind = ""
            app.refresh()
        }
    }

    Job {
        id: tilesJob
        property int count
        onFinished: code => {
            if (code === 0)
                app.notice(count === 1 ? qsTr("Tile added") : qsTr("Tiles added"),
                           qsTr("It is in your Steam library."))
            else
                app.notice(qsTr("Tiles not added"), app.tileFailure(code, error))
        }
    }

    Job {
        id: resetJob
        property string name
        onFinished: code => app.notice(code === 0 ? qsTr("Default settings restored") : qsTr("Restore failed"),
                                       code === 0 ? qsTr("%1 starts with the Pocknix defaults.").arg(name) : error)
    }

    TabPage {
        title: qsTr("Store")

        QQC2.Label {
            visible: !app.loaded
            text: qsTr("Loading…")
            color: Theme.textMuted
        }
        QQC2.Label {
            Layout.fillWidth: true
            visible: app.loaded && app.store.entries.length === 0
            text: qsTr("Nothing to show. Run an update first: the store lists what the Pocknix repository offers.")
            color: Theme.textMuted
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: app.store.sections

            ColumnLayout {
                id: section
                required property var modelData
                readonly property bool emulation: modelData.id === "emulation"
                readonly property var tiles: app.installedTiles(modelData.id)

                Layout.fillWidth: true
                spacing: Theme.spacing

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.spacing
                    spacing: Theme.spacing

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        QQC2.Label {
                            Layout.fillWidth: true
                            text: section.modelData.name
                            font.bold: true
                            font.pointSize: Theme.titleFontSize
                        }
                        QQC2.Label {
                            Layout.fillWidth: true
                            visible: section.emulation
                            text: app.store.mode === "all" ? qsTr("Everything installed as one set")
                                : app.store.mode === "pick" ? qsTr("Your pick of emulators")
                                : qsTr("Nothing installed yet")
                            color: Theme.textMuted
                            font.pointSize: Theme.smallFontSize
                        }
                    }
                    QQC2.Button {
                        visible: section.tiles.length > 0
                        enabled: !tilesJob.running
                        implicitHeight: Theme.touchTarget
                        text: qsTr("Add Steam tiles")
                        onClicked: app.addTiles(section.tiles)
                    }
                    QQC2.Button {
                        visible: section.emulation && app.store.mode !== "none"
                        enabled: !actionJob.running
                        implicitHeight: Theme.touchTarget
                        text: qsTr("Remove all")
                        onClicked: app.ask({
                            title: qsTr("Remove all emulation?"),
                            text: qsTr("ES-DE, Steam ROM Manager and every emulator are uninstalled, with their Steam tiles. Your ROMs, BIOS files, saves and settings are kept, so installing again brings everything back as it was."),
                            confirmText: qsTr("Remove all"),
                            hold: true,
                            danger: true,
                            yes: () => app.act("remove-all", [], qsTr("Removing emulation"))
                        })
                    }
                    QQC2.Button {
                        visible: section.emulation && app.store.mode !== "all"
                        enabled: !actionJob.running
                        implicitHeight: Theme.touchTarget
                        text: qsTr("Install all")
                        palette.button: Theme.accent
                        palette.buttonText: Theme.accentText
                        onClicked: app.ask({
                            title: qsTr("Install all emulation?"),
                            text: qsTr("ES-DE, Steam ROM Manager and every emulator, kept up to date as one set. A large download with a full system update."),
                            confirmText: qsTr("Install all"),
                            yes: () => app.act("install-all", [], qsTr("Installing emulation"))
                        })
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.spacing

                    Repeater {
                        model: app.inSection(section.modelData.id)

                        Tile {
                            required property var modelData
                            icon: modelData.icon
                            title: modelData.name
                            subtitle: modelData.description
                            badge: modelData.installed ? qsTr("Installed") : ""
                            badgeTone: "positive"
                            busy: actionJob.running && (app.acting.includes(modelData.id)
                                || (app.actingKind.endsWith("-all") && section.emulation))
                            onClicked: {
                                sheet.entry = modelData
                                sheet.open()
                            }
                        }
                    }
                }
            }
        }
    }

    EntrySheet {
        id: sheet
        locked: actionJob.running
        onInstall: id => app.install(id)
        onRemove: id => app.remove(id)
        onReset: id => app.reset(id)
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
        job: actionJob
        detached: true
    }
}
