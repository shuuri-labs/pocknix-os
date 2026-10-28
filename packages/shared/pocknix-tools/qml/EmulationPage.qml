import QtCore
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import Pocknix.Ui

TabPage {
    id: page
    property var app
    title: qsTr("Emulation")
    icon: "input-gamepad-symbolic"

    readonly property string romsInit: "/usr/bin/pocknix-roms-init"
    readonly property string home: StandardPaths.writableLocation(StandardPaths.HomeLocation).toString().replace("file://", "")
    readonly property string cards: "/run/media/" + home.split("/").pop()
    // "" = emulation is not installed (no pocknix-roms-init to ask)
    property string romsDir: ""
    property bool loaded: false
    readonly property bool busy: romsCheck.running || romsSet.running

    function shortPath(path) {
        return path.startsWith(cards + "/") ? path.slice(cards.length + 1)
            : path.startsWith(home + "/") ? "~" + path.slice(home.length) : path
    }
    // The script's errors carry its name for the terminal; a dialog shows just the sentence.
    function reason(text) {
        const t = text.replace(/^pocknix-roms-init: /gm, "")
        return t.charAt(0).toUpperCase() + t.slice(1)
    }
    function refresh() {
        romsWhere.start([romsInit, "--where"])
    }
    function pickRoms() {
        cardsJob.start(["/usr/bin/find", cards, "-mindepth", "1", "-maxdepth", "1", "-type", "d"])
    }
    // Listed per tap, so a card put in while Tools is open shows; no cards = find fails, none listed.
    function openPicker(cardPaths) {
        const def = home + "/Emulation/ROMs"
        const p = [{ label: qsTr("Internal storage"), detail: "~", path: home, icon: "drive-harddisk-symbolic", browse: true }]
        for (const c of cardPaths.sort())
            p.push({ label: qsTr("SD card %1").arg(c.split("/").pop()), detail: "",
                     path: c, icon: "media-flash-sd-mmc-symbolic", browse: true })
        if (romsDir !== def)
            p.push({ label: qsTr("Default folder"), detail: "~/Emulation/ROMs", path: def,
                     icon: "edit-undo-symbolic", browse: false })
        folders.places = p
        folders.open()
    }

    Component.onCompleted: refresh()

    Job {
        id: cardsJob
        onFinished: code => page.openPicker(code === 0 ? output.split("\n").filter(l => l) : [])
    }

    Job {
        id: romsWhere
        onFinished: code => {
            // an older pocknix-roms-init has no --where and runs its full seed instead
            page.romsDir = code === 0 && output.trim().startsWith("/") ? output.trim() : ""
            page.loaded = true
        }
    }
    // A dry run first, so the confirm names exactly the configs that change.
    Job {
        id: romsCheck
        property string target
        property var names: []
        onFinished: code => {
            if (code !== 0) {
                page.app.notice(qsTr("ROMs folder not changed"), page.reason(error))
                return
            }
            names = output.split("\n").filter(l => l).map(l => l.split("\t")[0])
                .filter((n, i, a) => a.indexOf(n) === i)
            page.app.ask({
                title: qsTr("Use %1 for your games?").arg(page.shortPath(target)),
                text: (names.length > 0 ? qsTr("%1 will look for games there.").arg(names.join(", ")) + "\n\n" : "")
                    + qsTr("No files are moved: copy your games there yourself. A folder for each system is created.")
                    + (target.startsWith(page.cards + "/")
                       ? "\n\n" + qsTr("The card's name is part of the folder, so a card with another name is a different folder.") : ""),
                confirmText: qsTr("Use this folder"),
                yes: () => romsSet.start([page.romsInit, "--roms", target])
            })
        }
    }
    Job {
        id: romsSet
        onFinished: code => {
            page.refresh()
            page.app.notice(code === 0 ? qsTr("ROMs folder changed") : qsTr("ROMs folder not changed"),
                            code !== 0 ? page.reason(error)
                            : romsCheck.names.indexOf("Steam ROM Manager") >= 0
                              ? qsTr("Game tiles you made with Steam ROM Manager still point at the old folder: open it, then Add Games and Save to Steam again.")
                              : qsTr("ES-DE and the emulators look there from now on."))
        }
    }

    QQC2.Label {
        Layout.fillWidth: true
        visible: page.loaded
        text: page.romsDir === "" ? qsTr("Emulation is not installed. Install it from the Pocknix Store, under Emulation.")
                                  : qsTr("Where ES-DE and the emulators look for your games.")
        color: Theme.textMuted
        wrapMode: Text.WordWrap
    }

    ActionRow {
        visible: page.romsDir !== ""
        title: qsTr("ROMs folder")
        description: page.shortPath(page.romsDir)
        busy: page.busy

        QQC2.Button {
            enabled: !page.busy
            implicitHeight: Theme.touchTarget
            text: qsTr("Change")
            onClicked: page.pickRoms()
        }
    }

    FolderSheet {
        id: folders
        title: qsTr("Where are your games?")
        onPicked: path => {
            romsCheck.target = path
            romsCheck.start([page.romsInit, "--roms", path, "--dry-run"])
        }
    }
}
