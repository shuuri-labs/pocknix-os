import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Pocknix.Ui

// The children are the tab pages (TabPage).
QQC2.ApplicationWindow {
    id: root
    default property alias pages: stack.data
    property alias currentIndex: strip.currentIndex

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
        highlight: Theme.accent
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

    header: TabStrip {
        id: strip
        visible: stack.children.length > 1
        titles: Array.from(stack.children, page => page.title || "")
    }

    StackLayout {
        id: stack
        anchors.fill: parent
        currentIndex: strip.currentIndex
        // Monochrome theme icons take Kirigami's text colour.
        Kirigami.Theme.inherit: false
        Kirigami.Theme.textColor: Theme.text
        Kirigami.Theme.backgroundColor: Theme.background
        Kirigami.Theme.highlightColor: Theme.accent
    }
}
