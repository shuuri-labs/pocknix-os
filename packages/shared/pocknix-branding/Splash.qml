/*
    Pocknix OS splash: the wordmark on the same field as the wallpaper and the
    Plymouth theme, so boot -> splash -> desktop is one continuous surface.

    ksplashqml drives `stage` as startup progresses; stage 2 is "show yourself".
    Nothing here waits on a later stage, because Plasma Mobile's shell does not
    emit the full sequence - the unit's own exit is what takes the splash away.
*/
import QtQuick

Rectangle {
    id: root
    color: "#202126"

    property int stage

    onStageChanged: {
        if (stage == 2) {
            fadeIn.running = true;
        }
    }

    Image {
        id: wordmark
        anchors.centerIn: parent
        // authored at 787px wide; cap at 45% of the screen so it holds its
        // proportions on any panel rather than being stretched to fit
        width: Math.min(787, parent.width * 0.45)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        source: "images/wordmark.png"
        opacity: 0
    }

    OpacityAnimator {
        id: fadeIn
        target: wordmark
        from: 0
        to: 1
        duration: 400
        running: false
    }
}
