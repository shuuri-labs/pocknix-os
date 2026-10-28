import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Pocknix.Ui

// The children are the tab pages (TabPage).
QQC2.ApplicationWindow {
    id: root
    default property alias pages: stack.data
    property alias currentIndex: rail.currentIndex

    visible: true
    visibility: Host.gamescope ? Window.FullScreen : Window.AutomaticVisibility
    width: Theme.unit * 44
    height: Theme.unit * 26
    color: Theme.background

    palette {
        window: Theme.background
        windowText: Theme.text
        base: Theme.surface
        alternateBase: Theme.surfaceHigh
        text: Theme.text
        button: Theme.surfaceHigh
        buttonText: Theme.text
        highlight: Theme.accentFill
        highlightedText: Theme.accentText
        placeholderText: Theme.textMuted
        mid: Theme.border
        // Basic fills switches, progress bars and busy indicators with `dark`.
        dark: Theme.accent
        light: Theme.surfaceHigh
        midlight: Theme.surfaceHigh
        shadow: "#000000"
        toolTipBase: Theme.surfaceHigh
        toolTipText: Theme.text
    }

    // { title, text, confirmText, hold, danger, yes }: yes() runs on confirm.
    function ask(o) {
        askSheet.title = o.title
        askSheet.text = o.text || ""
        askSheet.confirmText = o.confirmText || qsTr("OK")
        askSheet.cancelText = o.notice ? "" : qsTr("Cancel")
        askSheet.hold = !!o.hold
        askSheet.danger = !!o.danger
        askSheet.yes = o.yes || null
        askSheet.open()
    }
    function notice(title, text) {
        ask({ title: title, text: text, notice: true })
    }

    // Only the TabPage children are pages: a Repeater making them sits among them.
    readonly property var tabPages: Array.from(stack.children).filter(c => c instanceof TabPage)

    RowLayout {
        anchors.fill: parent
        spacing: 0

        NavRail {
            id: rail
            Layout.fillHeight: true
            visible: root.tabPages.length > 1
            pages: root.tabPages.map(p => ({ title: p.title, icon: p.icon }))
        }

        StackLayout {
            id: stack
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: rail.currentIndex
            // Monochrome theme icons take Kirigami's text colour.
            Kirigami.Theme.inherit: false
            Kirigami.Theme.textColor: Theme.text
            Kirigami.Theme.backgroundColor: Theme.background
            Kirigami.Theme.highlightColor: Theme.accent
        }
    }

    ConfirmSheet {
        id: askSheet
        property var yes: null
        onAccepted: {
            const f = yes
            yes = null
            if (f)
                f()
        }
    }
}
