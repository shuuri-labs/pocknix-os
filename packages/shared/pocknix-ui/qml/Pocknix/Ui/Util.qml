pragma Singleton
import QtCore
import QtQuick

// Paths and parsing both apps need.
QtObject {
    readonly property string home: StandardPaths.writableLocation(StandardPaths.HomeLocation).toString().replace("file://", "")
    // where udisks mounts the user's cards
    readonly property string cards: "/run/media/" + home.split("/").pop()

    // A card path from its label, a home path as ~.
    function shortPath(path) {
        return path.startsWith(cards + "/") ? path.slice(cards.length + 1)
            : path.startsWith(home + "/") ? "~" + path.slice(home.length) : path
    }
    // key=value lines, as the CLIs' plain status prints them
    function kv(text) {
        const r = {}
        text.split("\n").forEach(l => {
            const i = l.indexOf("=")
            if (i > 0)
                r[l.slice(0, i)] = l.slice(i + 1)
        })
        return r
    }
}
