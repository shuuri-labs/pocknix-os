import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import Pocknix.Ui

// A Flickable, not a ScrollView: ScrollView drops mouse drags and flicks only for touch events,
// and gamescope can hand a window touch as Steam's emulated pointer.
Flickable {
    id: page
    property string title
    default property alias content: column.data

    contentWidth: width
    contentHeight: column.implicitHeight + Theme.spacing * 2
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

    ColumnLayout {
        id: column
        x: Theme.spacing
        y: Theme.spacing
        width: page.width - Theme.spacing * 2
        spacing: Theme.spacing
    }
}
