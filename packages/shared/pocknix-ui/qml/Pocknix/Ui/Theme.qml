pragma Singleton
import QtQuick
import org.kde.kirigami as Kirigami

// Every colour and size the apps draw with: a reskin edits this file and nothing else.
QtObject {
    readonly property color background: "#14161b"
    readonly property color surface: "#1e2128"
    readonly property color surfaceHigh: "#2a2e37"
    readonly property color border: "#363b46"
    readonly property color text: "#eceff4"
    readonly property color textMuted: "#9aa2b1"
    // The plain colours are for text and indicators on our surfaces; a *Fill colour is for a
    // background that carries accentText. Each pair clears 4.5:1 (WCAG AA) in its own role.
    readonly property color accent: "#3d8bfd"
    readonly property color accentFill: "#2f6fd6"
    readonly property color accentText: "#ffffff"
    readonly property color accentSoft: Qt.rgba(accent.r, accent.g, accent.b, 0.3)
    readonly property color positive: "#3fb97a"
    readonly property color warning: "#e9a23b"
    readonly property color negative: "#ec5f57"
    readonly property color negativeFill: "#c93a33"

    readonly property real unit: Kirigami.Units.gridUnit
    readonly property real spacing: Kirigami.Units.largeSpacing
    readonly property real smallSpacing: Kirigami.Units.smallSpacing
    readonly property real radius: Kirigami.Units.smallSpacing * 3
    // Never below 48 logical px, the smallest target a thumb hits reliably (Material's minimum).
    readonly property real touchTarget: Math.max(48, unit * 2.75)
    readonly property real tileWidth: unit * 9
    readonly property real railWidth: unit * 5.5
    readonly property real iconSize: Kirigami.Units.iconSizes.large
    readonly property real fontSize: Kirigami.Theme.defaultFont.pointSize
    readonly property real titleFontSize: fontSize * 1.3
    readonly property real smallFontSize: fontSize * 0.85

    function toneColor(tone) {
        switch (tone) {
        case "positive": return positive
        case "warning": return warning
        case "negative": return negative
        case "accent": return accent
        default: return textMuted
        }
    }
}
