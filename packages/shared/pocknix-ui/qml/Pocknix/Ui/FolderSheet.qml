import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import org.kde.kirigami as Kirigami
import Pocknix.Ui

// Pick a folder by touch: the app's places, each browsed from its own root (Up stops there, so
// the pick stays inside the user's storage). Qt's own FolderDialog falls back to a small desktop
// tree under gamescope.
Sheet {
    id: sheet
    property string title
    // [{ label, detail, path, icon, browse }]: browse = open the folder, else pick it as it is
    property var places: []
    property string newFolderName: "ROMs"
    signal picked(string path)

    property var place: null
    property string folder: ""
    readonly property bool browsing: place !== null
    // FolderListModel lists the working directory in place of a folder that is not there (a
    // card taken out), so check what it actually loaded.
    readonly property bool missing: dirs.status === FolderListModel.Ready
        && decodeURIComponent(dirs.folder.toString().replace("file://", "")) !== folder
    readonly property string shownPath: !place ? ""
        : [place.label].concat(folder.slice(place.path.length).split("/").filter(p => p)).join(" › ")

    function browse(path) {
        folder = path.length > 1 && path.endsWith("/") ? path.slice(0, -1) : path
        naming = false
    }
    // Folder before place, so the sheet never browses with no folder.
    function activate(e) {
        if (browsing) {
            browse(e.path)
        } else if (e.browse) {
            browse(e.path)
            place = e
        } else {
            choose(e.path)
        }
    }
    function up() {
        browse(folder.slice(0, folder.lastIndexOf("/")) || "/")
    }
    function choose(path) {
        close()
        picked(path)
    }
    property bool naming: false

    height: parent ? parent.height - Theme.spacing * 4 : 0
    onOpened: {
        place = null
        naming = false
    }

    FolderListModel {
        id: dirs
        folder: sheet.folder !== "" ? "file://" + sheet.folder : ""
        showFiles: false
        showDotAndDotDot: false
        showHidden: false
        // lost+found and other root-only folders cannot be opened, let alone hold games
        showOnlyReadable: true
        sortCaseSensitive: false
    }

    Job {
        id: mkdirJob
        property string path
        onFinished: code => {
            if (code === 0)
                sheet.browse(path)
            else
                mkdirError.text = error
        }
    }

    contentItem: ColumnLayout {
        spacing: Theme.spacing

        QQC2.Label {
            Layout.fillWidth: true
            text: sheet.browsing ? sheet.shownPath : sheet.title
            font.bold: true
            font.pointSize: Theme.titleFontSize
            elide: Text.ElideLeft
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            spacing: Theme.smallSpacing
            model: !sheet.browsing ? sheet.places : sheet.missing ? [] : dirs
            QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

            delegate: Rectangle {
                id: row
                required property var model
                readonly property var entry: sheet.browsing
                    ? { label: model.fileName, detail: "", path: model.filePath, icon: "folder-symbolic" }
                    : model.modelData

                width: ListView.view.width
                height: Math.max(Theme.touchTarget, rowLayout.implicitHeight + Theme.smallSpacing * 2)
                radius: Theme.radius
                color: tap.pressed ? Theme.surfaceHigh : Theme.background

                RowLayout {
                    id: rowLayout
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacing
                    anchors.rightMargin: Theme.spacing
                    spacing: Theme.spacing

                    Kirigami.Icon {
                        implicitWidth: Theme.iconSize * 0.6
                        implicitHeight: implicitWidth
                        source: row.entry.icon || "folder-symbolic"
                        isMask: true
                        color: Theme.text
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        QQC2.Label {
                            Layout.fillWidth: true
                            text: row.entry.label
                            elide: Text.ElideRight
                        }
                        QQC2.Label {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: row.entry.detail || ""
                            color: Theme.textMuted
                            font.pointSize: Theme.smallFontSize
                            elide: Text.ElideMiddle
                        }
                    }
                    Kirigami.Icon {
                        visible: sheet.browsing || row.entry.browse
                        implicitWidth: Theme.iconSize * 0.45
                        implicitHeight: implicitWidth
                        source: "go-next-symbolic"
                        isMask: true
                        color: Theme.textMuted
                    }
                }

                TapHandler {
                    id: tap
                    // One call, nothing after it: the sheet swaps or reloads the model, which
                    // destroys this row mid-handler and its ids (sheet included) stop resolving.
                    onTapped: sheet.activate(row.entry)
                }
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            visible: sheet.browsing && dirs.status === FolderListModel.Ready && (sheet.missing || dirs.count === 0)
            text: sheet.missing ? qsTr("This folder is not there any more.") : qsTr("No folders in here yet.")
            color: Theme.textMuted
        }

        // Steam's keyboard (Steam + X) types here in game mode.
        RowLayout {
            Layout.fillWidth: true
            visible: sheet.naming
            spacing: Theme.spacing

            QQC2.TextField {
                id: nameField
                Layout.fillWidth: true
                implicitHeight: Theme.touchTarget
                placeholderText: qsTr("Folder name")
                onAccepted: if (create.enabled) create.clicked()
            }
            Button {
                id: create
                enabled: !mkdirJob.running && /^[^/]+$/.test(nameField.text.trim()) && nameField.text.trim() !== "."
                    && nameField.text.trim() !== ".."
                text: qsTr("Create")
                onClicked: {
                    mkdirError.text = ""
                    mkdirJob.path = sheet.folder.replace(/\/$/, "") + "/" + nameField.text.trim()
                    mkdirJob.start(["/usr/bin/mkdir", "--", mkdirJob.path])
                }
            }
        }
        QQC2.Label {
            id: mkdirError
            Layout.fillWidth: true
            visible: sheet.naming && text !== ""
            color: Theme.negative
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing

            Button {
                visible: sheet.browsing
                icon.name: "go-up-symbolic"
                text: sheet.place && sheet.folder === sheet.place.path ? qsTr("Places") : qsTr("Up")
                onClicked: sheet.place && sheet.folder === sheet.place.path ? sheet.place = null : sheet.up()
            }
            Button {
                visible: sheet.browsing && !sheet.naming && !sheet.missing
                icon.name: "folder-new-symbolic"
                text: qsTr("New folder")
                onClicked: {
                    nameField.text = sheet.newFolderName
                    mkdirError.text = ""
                    sheet.naming = true
                }
            }
            Item { Layout.fillWidth: true }
            Button {
                visible: !sheet.browsing
                text: qsTr("Cancel")
                onClicked: sheet.close()
            }
            Button {
                visible: sheet.browsing
                enabled: !sheet.missing
                text: qsTr("Use this folder")
                kind: Button.Primary
                onClicked: sheet.choose(sheet.folder)
            }
        }
    }
}
