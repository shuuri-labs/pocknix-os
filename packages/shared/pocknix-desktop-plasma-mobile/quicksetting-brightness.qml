// SPDX-License-Identifier: GPL-2.0-or-later
//
// Quick setting tile that cycles screen brightness through fixed steps.
// Uses the same PowerDevil interface as the shell's own brightness slider.

import QtQuick

import org.kde.plasma.private.mobileshell.quicksettingsplugin as QS
import org.kde.plasma.private.mobileshell.screenbrightnessplugin as SB

QS.QuickSetting {
    id: root

    // Steps in percent, descending. Tapping goes to the next lower step and
    // wraps back to 100% from the lowest one.
    readonly property var steps: [100, 75, 50, 25, 10]
    readonly property real percent: util.maxBrightness > 0 ? Math.round(100 * util.brightness / util.maxBrightness) : 0

    text: "Brightness"
    icon: percent > 60 ? "brightness-high" : "brightness-low"
    status: percent + "%"
    enabled: false
    // brightnessAvailable freezes at construction; maxBrightness notifies, so the timer below heals a late PowerDevil.
    available: util.maxBrightness > 0

    function toggle() {
        if (util.maxBrightness <= 0) {
            return;
        }
        let target = root.steps[0];
        for (let i = 0; i < root.steps.length; ++i) {
            if (root.steps[i] < root.percent - 1) {
                target = root.steps[i];
                break;
            }
        }
        util.brightness = Math.max(1, Math.round(util.maxBrightness * target / 100));
    }

    SB.ScreenBrightnessUtil {
        id: util
    }

    // ScreenBrightnessUtil only fetches on setup and on change signals, so if PowerDevil
    // was not on the bus yet it never gets values. Poll until it answers, then stop.
    Timer {
        interval: 1500
        repeat: true
        running: util.maxBrightness <= 0
        onTriggered: {
            util.fetchBrightness();
            util.fetchMaxBrightness();
        }
    }
}
