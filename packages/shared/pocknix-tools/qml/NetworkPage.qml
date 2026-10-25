import QtCore
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
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
    // which of tailscale / wireguard-tools are installed: their sections show only then
    property var installed: ({})
    // tailscale status --json; the login URL while a sign-in waits, and its QR code file
    property var ts: ({})
    property string tsUrl: ""
    property string tsQr: ""
    // the coordination server Tailscale uses: its own unless signed in to e.g. Headscale
    readonly property string defaultServer: "https://controlplane.tailscale.com"
    property string tsServer: defaultServer
    readonly property bool customServer: tsServer.replace(/\/+$/, "") !== defaultServer
    // empty after `tailscale logout`, which resets every setting: deck then needs root to sign in
    property string tsOperator: ""
    property string pendingServer: ""
    // NetworkManager's WireGuard connections: {uuid, name, active}
    property var tunnels: []

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
        pkgJob.start(["/usr/bin/pacman", "-Qq", "tailscale", "wireguard-tools"])
        wgJob.start(["/usr/bin/nmcli", "-g", "UUID,TYPE,ACTIVE,NAME", "connection", "show"])
    }
    // --operator and --login-server every time: `up` clears an operator it is not given, and
    // refuses to run without a non-default server it was signed in with.
    function tailscaleUp(server) {
        tsUrl = ""
        tsQr = ""
        if (!tsOperator) {
            pendingServer = server || tsServer
            operatorJob.start(["/usr/bin/pocknix-store", "setup", "tailscale"], { root: true })
            return
        }
        upJob.start(["/bin/sh", "-c", 'exec tailscale up --operator="$(id -un)" --timeout=5m --login-server="$1"',
                     "sh", server || tsServer])
    }
    function quick(argv) {
        quickJob.start(argv)
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
        shareSheet.open()
    }
    // The password goes on stdin, never on a command line other users can read.
    function shareWithPassword(pw) {
        shareOnJob.start(["/usr/bin/pocknix-share", "on", "--password-stdin"], { root: true, input: true })
        shareOnJob.send(pw)
        shareOnJob.closeInput()
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
        id: pkgJob
        onFinished: {
            const r = {}
            output.split("\n").forEach(n => { if (n) r[n] = true })
            page.installed = r
            if (r.tailscale) {
                tsJob.start(["/usr/bin/tailscale", "status", "--json"])
                prefsJob.start(["/usr/bin/tailscale", "debug", "prefs"])
            }
        }
    }
    Job {
        id: tsJob
        onFinished: code => {
            try {
                page.ts = JSON.parse(output)
            } catch (e) {
                page.ts = {}
            }
        }
    }
    Job {
        id: prefsJob
        onFinished: code => {
            try {
                const prefs = JSON.parse(output)
                page.tsServer = prefs.ControlURL || page.defaultServer
                page.tsOperator = prefs.OperatorUser || ""
            } catch (e) {
                page.tsServer = page.defaultServer
            }
        }
    }
    Job {
        id: operatorJob
        onFinished: code => {
            if (code !== 0) {
                page.app.notice(qsTr("Tailscale could not be set up"), error)
                return
            }
            page.tsOperator = "restored"
            page.tailscaleUp(page.pendingServer)
        }
    }
    // The login link is printed on a line of its own; error texts quote URLs inside commands.
    Job {
        id: upJob
        onLine: text => {
            const m = text.match(/^\s*(https?:\/\/\S+)\s*$/)
            if (m && !page.tsUrl) {
                page.tsUrl = m[1]
                qrJob.start(["/bin/sh", "-c", 'f="${XDG_RUNTIME_DIR:-/tmp}/pocknix-tailscale-qr.svg"; qrencode -t SVG -o "$f" "$1" && echo "$f"',
                             "sh", m[1]])
            }
        }
        onFinished: code => {
            const waited = page.tsUrl !== ""
            page.tsUrl = ""
            page.tsQr = ""
            page.refresh()
            if (code !== 0)
                page.app.notice(qsTr("Tailscale did not connect"),
                                waited ? qsTr("Sign-in did not finish within 5 minutes. Try again.") : error)
        }
    }
    Job {
        id: qrJob
        onFinished: code => page.tsQr = code === 0 ? "file://" + output.trim() : ""
    }
    Job {
        id: quickJob
        onFinished: code => {
            page.refresh()
            if (code !== 0)
                page.app.notice(qsTr("That did not work"), error)
        }
    }
    // -g escapes ':' in a name as '\:', and the name is the last field
    Job {
        id: wgJob
        onFinished: page.tunnels = output.split("\n").map(l => l.split(":")).filter(f => f[1] === "wireguard")
            .map(f => ({ uuid: f[0], active: f[2] === "yes", name: f.slice(3).join(":").replace(/\\:/g, ":") }))
    }
    Job {
        id: importJob
        onFinished: code => {
            page.refresh()
            if (code === 0)
                page.app.notice(qsTr("Tunnel added"), qsTr("It is off and does not connect on its own: switch it on here."))
            else
                page.app.notice(qsTr("Import failed"), error)
        }
    }
    FileDialog {
        id: picker
        title: qsTr("Import a WireGuard tunnel")
        nameFilters: [qsTr("WireGuard tunnels (*.conf)")]
        currentFolder: StandardPaths.writableLocation(StandardPaths.DownloadLocation)
        onAccepted: importJob.start(["/usr/lib/pocknix-tools/pocknix-wg-import",
                                     decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, ""))])
    }

    Job {
        id: shareOnJob
        onFinished: code => {
            page.refresh()
            if (code === 0)
                page.app.notice(qsTr("File sharing is on"),
                    qsTr("On another computer, open smb://pocknix.local%1 and sign in as deck with deck's password.")
                        .arg(page.addresses ? qsTr(" (or smb://%1)").arg(page.addresses.split(" ")[0]) : ""))
            else
                page.app.notice(qsTr("File sharing stayed off"), error)
        }
    }
    QQC2.Popup {
        id: shareSheet
        parent: QQC2.Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(parent ? parent.width - Theme.spacing * 4 : 0, Theme.unit * 32)
        modal: true
        padding: Theme.spacing * 1.5
        background: Rectangle {
            color: Theme.surface
            radius: Theme.radius
            border.color: Theme.border
        }
        onOpened: {
            password.text = ""
            password.forceActiveFocus()
        }
        function go() {
            if (password.text === "")
                return
            close()
            page.shareWithPassword(password.text)
            password.text = ""
        }

        contentItem: ColumnLayout {
            spacing: Theme.spacing
            QQC2.Label {
                Layout.fillWidth: true
                text: qsTr("Share your home folder?")
                font.bold: true
                font.pointSize: Theme.titleFontSize
            }
            QQC2.Label {
                Layout.fillWidth: true
                text: qsTr("Anyone on this network who knows deck's password can then read and write every file in it: games, saves and settings, but also your Steam login and SSH keys. If deck still has the password Pocknix shipped with, change it first (passwd in a terminal).\n\nYou sign in as deck with deck's password. It stays on, across reboots, until you turn it off here.")
                wrapMode: Text.WordWrap
            }
            QQC2.TextField {
                id: password
                Layout.fillWidth: true
                implicitHeight: Theme.touchTarget
                echoMode: TextInput.Password
                placeholderText: qsTr("deck's password")
                onAccepted: shareSheet.go()
            }
            QQC2.Label {
                visible: Host.gamescope
                Layout.fillWidth: true
                text: qsTr("In game mode, open the keyboard with STEAM + X.")
                color: Theme.textMuted
                font.pointSize: Theme.smallFontSize
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: Theme.spacing
                QQC2.Button {
                    implicitHeight: Theme.touchTarget
                    text: qsTr("Cancel")
                    onClicked: shareSheet.close()
                }
                QQC2.Button {
                    implicitHeight: Theme.touchTarget
                    text: qsTr("Turn on")
                    enabled: password.text !== ""
                    palette.button: Theme.negative
                    palette.buttonText: Theme.accentText
                    onClicked: shareSheet.go()
                }
            }
        }
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
        id: shareRow
        title: qsTr("File sharing (SMB)")
        // On from before sign-in passwords: Samba refuses every login until one is set.
        readonly property bool noPassword: page.share.state === "on" && page.share.password !== "yes"
        description: noPassword ? qsTr("On, but nobody can sign in yet: set the sharing password.")
            : page.share.state === "on" ? qsTr("On: sign in as deck with deck's password. Changed that password? Turn sharing off and on again.")
            : qsTr("Off")
        QQC2.Button {
            visible: shareRow.noPassword
            implicitHeight: Theme.touchTarget
            text: qsTr("Set password")
            palette.button: Theme.accent
            palette.buttonText: Theme.accentText
            onClicked: shareSheet.open()
        }
        QQC2.Switch {
            checkable: false
            checked: page.share.state === "on"
            enabled: !page.app.logJobRunning && !shareOnJob.running && page.share.state !== undefined
            onClicked: checked ? page.toggle("/usr/bin/pocknix-share", false) : page.shareOn()
        }
    }

    QQC2.Label {
        visible: !!page.installed.tailscale
        Layout.topMargin: Theme.spacing
        text: qsTr("Tailscale")
        font.bold: true
        font.pointSize: Theme.titleFontSize
    }
    ActionRow {
        id: tsRow
        readonly property string tsState: page.ts.BackendState || ""
        readonly property var tsSelf: page.ts.Self || {}
        visible: !!page.installed.tailscale
        title: qsTr("Tailscale")
        description: upJob.running ? qsTr("Connecting…")
            : tsRow.tsState === "Running" ? qsTr("Connected as %1 (%2)").arg(tsSelf.HostName).arg((tsSelf.TailscaleIPs || [""])[0])
                + (page.customServer ? qsTr(" via %1").arg(page.tsServer.replace(/^https?:\/\//, "")) : "")
            : tsRow.tsState === "Stopped" ? qsTr("Off")
            : tsRow.tsState === "NeedsLogin" ? qsTr("Signed out")
            : tsRow.tsState === "Starting" ? qsTr("Connecting…")
            : qsTr("The Tailscale service is not running")
        busy: upJob.running || quickJob.running || operatorJob.running
        QQC2.Button {
            visible: (tsRow.tsState === "Running" || tsRow.tsState === "Stopped") && !upJob.running
            implicitHeight: Theme.touchTarget
            text: qsTr("Sign out")
            onClicked: page.quick(["/usr/bin/tailscale", "logout"])
        }
        QQC2.Button {
            visible: tsRow.tsState === "NeedsLogin" && !upJob.running
            implicitHeight: Theme.touchTarget
            text: qsTr("Sign in")
            palette.button: Theme.accent
            palette.buttonText: Theme.accentText
            enabled: !ownServer.checked || /^https?:\/\/\S+$/.test(serverField.text.trim())
            onClicked: page.tailscaleUp(ownServer.checked ? serverField.text.trim() : page.defaultServer)
        }
        QQC2.Switch {
            visible: tsRow.tsState === "Running" || tsRow.tsState === "Stopped"
            checkable: false
            checked: tsRow.tsState === "Running"
            enabled: !upJob.running && !quickJob.running
            onClicked: checked ? page.quick(["/usr/bin/tailscale", "down"]) : page.tailscaleUp()
        }
    }
    ColumnLayout {
        visible: tsRow.visible && tsRow.tsState === "NeedsLogin" && !upJob.running
        Layout.fillWidth: true
        spacing: Theme.smallSpacing
        QQC2.CheckBox {
            id: ownServer
            text: qsTr("Use my own server (Headscale)")
            checked: page.customServer
        }
        QQC2.TextField {
            id: serverField
            visible: ownServer.checked
            Layout.fillWidth: true
            implicitHeight: Theme.touchTarget
            placeholderText: "https://headscale.example.com"
            text: page.customServer ? page.tsServer : ""
            inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
        }
        QQC2.Label {
            visible: ownServer.checked && Host.gamescope
            Layout.fillWidth: true
            text: qsTr("In game mode, open the keyboard with STEAM + X.")
            color: Theme.textMuted
            font.pointSize: Theme.smallFontSize
        }
    }
    Rectangle {
        visible: page.tsUrl !== ""
        Layout.fillWidth: true
        implicitHeight: qrRow.implicitHeight + Theme.spacing * 2
        radius: Theme.radius
        color: Theme.surface
        RowLayout {
            id: qrRow
            anchors.fill: parent
            anchors.margins: Theme.spacing
            spacing: Theme.spacing * 2
            Rectangle {
                implicitWidth: Theme.unit * 11
                implicitHeight: Theme.unit * 11
                color: "white"
                radius: Theme.radius
                Image {
                    anchors.fill: parent
                    anchors.margins: Theme.smallSpacing * 2
                    source: page.tsQr
                    cache: false
                    sourceSize.width: width
                    sourceSize.height: height
                    smooth: false
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                QQC2.Label {
                    Layout.fillWidth: true
                    text: qsTr("Scan with your phone to sign in, or open this link on any device:")
                    wrapMode: Text.WordWrap
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    text: page.tsUrl
                    color: Theme.accent
                    wrapMode: Text.WrapAnywhere
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    text: qsTr("This updates by itself once you have signed in (up to 5 minutes).")
                    color: Theme.textMuted
                    font.pointSize: Theme.smallFontSize
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    QQC2.Label {
        visible: !!page.installed["wireguard-tools"] || page.tunnels.length > 0
        Layout.topMargin: Theme.spacing
        text: qsTr("WireGuard")
        font.bold: true
        font.pointSize: Theme.titleFontSize
    }
    Repeater {
        model: page.tunnels
        ActionRow {
            required property var modelData
            title: modelData.name
            description: modelData.active ? qsTr("Connected") : qsTr("Off")
            busy: quickJob.running
            QQC2.Switch {
                checkable: false
                checked: modelData.active
                enabled: !quickJob.running
                onClicked: page.quick(["/usr/bin/nmcli", "connection", checked ? "down" : "up", "uuid", modelData.uuid])
            }
        }
    }
    ActionRow {
        visible: !!page.installed["wireguard-tools"] || page.tunnels.length > 0
        title: qsTr("Import a tunnel")
        description: qsTr("A .conf file from your VPN provider or your own server. It is added switched off.")
        busy: importJob.running
        QQC2.Button {
            implicitHeight: Theme.touchTarget
            text: qsTr("Import .conf")
            enabled: !importJob.running
            onClicked: picker.open()
        }
    }
}
