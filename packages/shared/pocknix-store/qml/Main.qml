import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import Pocknix.Ui

AppWindow {
    id: app
    title: qsTr("Pocknix Store")

    readonly property string cli: "/usr/bin/pocknix-store"
    readonly property string romsInit: "/usr/bin/pocknix-roms-init"
    property string romsDir: ""
    property var store: ({ mode: "none", job: "none", sections: [], entries: [] })
    property bool loaded: false
    property bool attached: false
    // what the running store job works on: its tiles show busy
    property var acting: []
    property string actingKind: ""
    // tiles to drop after a removal: an emulator's goes with its manifest, Moonlight's stays
    property var actingTiles: []
    // ids whose Steam tiles to offer once the status after an install is in
    property var offerTiles: []
    // ids whose install note to show once the status after an install is in
    property var offerNotes: []
    // Replaced only when the sections change, so a refresh after each action keeps the pages.
    property var sections: []
    readonly property var sectionIcons: ({
        emulation: "input-gamepad-symbolic", compatibility: "system-run-symbolic",
        network: "network-vpn-symbolic", streaming: "media-playback-start-symbolic",
        desktop: "monitor-symbolic"
    })

    function refresh() {
        statusJob.start([cli, "status", "--json"])
        // after an install or a removal too: emulation brings or takes pocknix-roms-init
        romsWhere.start([romsInit, "--where"])
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


    function act(kind, ids, title) {
        if (actionJob.running)
            return
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
                   : e.section === "compatibility" ? qsTr("Games set to %1 need another compatibility tool in Steam.").arg(e.name)
                   : e.section === "desktop" ? qsTr("If desktop mode uses it, pick another desktop in Pocknix Tools first.")
                   : qsTr("It can be installed again at any time.")),
            confirmText: qsTr("Remove"),
            danger: true,
            yes: () => {
                actingTiles = !emulation && e.tile ? [e.tile] : []
                act("remove", [id], qsTr("Removing %1").arg(e.name))
            }
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
        id: romsWhere
        onFinished: code => app.romsDir = code === 0 ? output.trim() : ""
    }

    Job {
        id: statusJob
        onFinished: code => {
            if (code === 0) {
                try {
                    app.store = JSON.parse(output)
                    if (JSON.stringify(app.store.sections) !== JSON.stringify(app.sections))
                        app.sections = app.store.sections
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
            const noted = app.store.entries.filter(e => app.offerNotes.includes(e.id) && e.installed && e.note)
            app.offerNotes = []
            if (offer.length === 0 && noted.length > 0)
                app.notice(qsTr("%1 is installed").arg(noted.map(e => e.name).join(", ")),
                           noted.map(e => e.note).filter((n, i, a) => a.indexOf(n) === i).join("\n"))
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
                if (app.actingKind === "install") {
                    app.offerTiles = app.acting
                    app.offerNotes = app.acting
                }
                else if (app.actingKind === "install-all")
                    app.offerTiles = app.store.entries.filter(e => e.section === "emulation").map(e => e.id)
                else if (app.actingKind === "remove" && app.actingTiles.length > 0)
                    untileJob.start(["/usr/bin/pocknix-tiles", "disable"].concat(app.actingTiles))
            }
            app.actingTiles = []
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
        id: untileJob
        onFinished: code => {
            if (code !== 0)
                app.notice(qsTr("Steam tile not removed"),
                           app.tileFailure(code, error) + " " + qsTr("You can delete the tile in Steam."))
        }
    }

    Job {
        id: resetJob
        property string name
        onFinished: code => app.notice(code === 0 ? qsTr("Default settings restored") : qsTr("Restore failed"),
                                       code === 0 ? qsTr("%1 starts with the Pocknix defaults.").arg(name) : error)
    }

    // One page per section. Until the status is in (or when it lists nothing) a single page
    // holds the message, so the rail stays hidden.
    Repeater {
        model: app.sections.length > 0 ? app.sections : [{ id: "", name: qsTr("Store") }]

        TabPage {
            id: section
            required property var modelData
            readonly property bool emulation: modelData.id === "emulation"
            readonly property var tiles: app.installedTiles(modelData.id)

            title: modelData.name
            icon: app.sectionIcons[modelData.id] || "applications-other-symbolic"

            QQC2.Label {
                visible: section.modelData.id === ""
                Layout.fillWidth: true
                text: !app.loaded ? qsTr("Loading…")
                    : qsTr("Nothing to show. Run an update first: the store lists what the Pocknix repository offers.")
                color: Theme.textMuted
                wrapMode: Text.WordWrap
            }

            ColumnLayout {
                visible: section.modelData.id !== ""
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

            // A Flow, so the actions wrap on a narrow panel instead of squeezing the title.
            Flow {
                id: actions
                // A child's visible reads false while the page is hidden, so testing the children
                // would hide this row for good after a visit to another page.
                readonly property bool installAllShown: section.emulation && app.store.mode !== "all"
                readonly property bool tilesShown: section.tiles.length > 0
                Layout.fillWidth: true
                visible: installAllShown || tilesShown
                spacing: Theme.spacing

                Button {
                    id: installAll
                    visible: actions.installAllShown
                    enabled: !actionJob.running
                    text: qsTr("Install all")
                    kind: Button.Primary
                    onClicked: app.ask({
                        title: qsTr("Install all emulation?"),
                        text: qsTr("ES-DE, Steam ROM Manager and every emulator, kept up to date as one set. A large download with a full system update."),
                        confirmText: qsTr("Install all"),
                        yes: () => app.act("install-all", [], qsTr("Installing emulation"))
                    })
                }
                Button {
                    id: addTiles
                    visible: actions.tilesShown
                    enabled: !tilesJob.running
                    text: qsTr("Add Steam tiles")
                    onClicked: app.addTiles(section.tiles)
                }
            }

            // Set in Pocknix Tools: the Store installs, Tools configures.
            QQC2.Label {
                Layout.fillWidth: true
                visible: section.emulation && app.store.mode !== "none" && app.romsDir !== ""
                text: qsTr("Your games go in %1. Change it in Pocknix Tools, under Emulation.").arg(Util.shortPath(app.romsDir))
                color: Theme.textMuted
                wrapMode: Text.WordWrap
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

            // Kept apart from Install all, at the end of the page: the one action here that takes
            // the whole section away.
            ActionRow {
                visible: section.emulation && app.store.mode !== "none"
                Layout.topMargin: Theme.spacing * 2
                title: qsTr("Remove all emulation")
                description: qsTr("Your ROMs, BIOS files, saves and settings are kept.")

                Button {
                    enabled: !actionJob.running
                    text: qsTr("Remove all")
                    kind: Button.Danger
                    onClicked: app.ask({
                        title: qsTr("Remove all emulation?"),
                        text: qsTr("ES-DE, Steam ROM Manager and every emulator are uninstalled, with their Steam tiles. Your ROMs, BIOS files, saves and settings are kept, so installing again brings everything back as it was."),
                        confirmText: qsTr("Remove all"),
                        hold: true,
                        danger: true,
                        yes: () => app.act("remove-all", [], qsTr("Removing emulation"))
                    })
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


    LogSheet {
        id: log
        job: actionJob
        detached: true
    }
}
