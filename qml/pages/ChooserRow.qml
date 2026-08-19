import QtQuick 2.0
import Sailfish.Silica 1.0
import ".." 1.0

// A tappable row that looks like a dropdown. Emits tapped(anchor) where
// anchor is this row, so the caller can attach a PillMenu to it.
BackgroundItem {
    id: root
    property string label: ""
    signal tapped(var anchor)

    width: parent.width
    height: Theme.itemSizeSmall
    onClicked: if (enabled) root.tapped(root)

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.highlighted ? FiatLuxTheme.amberMed : FiatLuxTheme.deepBg
        border.color: root.enabled ? FiatLuxTheme.amber : FiatLuxTheme.rim
        border.width: 1
        opacity: root.enabled ? 1.0 : 0.5
    }
    Row {
        anchors.centerIn: parent
        spacing: Theme.paddingSmall
        Text {
            text: root.label
            color: FiatLuxTheme.primaryText
            font.pixelSize: Theme.fontSizeSmall
            font.family: FiatLuxTheme.serif
            font.italic: true
        }
        Text {
            text: "▾"
            color: FiatLuxTheme.amber
            font.pixelSize: Theme.fontSizeSmall
        }
    }
}
