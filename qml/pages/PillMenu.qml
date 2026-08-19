import QtQuick 2.0
import Sailfish.Silica 1.0
import ".." 1.0

// Simple themed picker. Usage:
//   PillMenu { id: m; onPicked: function(idx){ ... } }
//   m.items = ["a","b","c"]; m.show(anchorItem)
// The anchor argument is accepted for API compatibility but the menu
// presents as a centered overlay.
Item {
    id: root
    property var items: []
    signal picked(int index)

    anchors.fill: parent
    visible: false
    z: 1000

    function show(anchor) { visible = true }
    function hide() { visible = false }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.8)
        MouseArea { anchors.fill: parent; onClicked: root.hide() }
    }

    SilicaFlickable {
            id: flick
            anchors.fill: parent
            contentHeight: Math.max(height, col.height + Theme.paddingLarge * 2)

            Column {
                id: col
                anchors.horizontalCenter: parent.horizontalCenter
                // Centre when it fits; otherwise start at the top and scroll.
                y: col.height + Theme.paddingLarge * 2 < flick.height
                   ? (flick.height - col.height) / 2
                   : Theme.paddingLarge
                width: parent.width - 2 * Theme.horizontalPageMargin
                spacing: Theme.paddingMedium

                Repeater {
                    model: root.items
                    delegate: BackgroundItem {
                        id: pillItem
                        width: parent.width
                        height: Theme.itemSizeMedium
                        onClicked: { root.hide(); root.picked(index) }
                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width
                            height: Theme.itemSizeSmall
                            radius: height / 2
                            color: pillItem.highlighted ? FiatLuxTheme.amberMed : FiatLuxTheme.surfaceOpaque
                            border.color: FiatLuxTheme.amber
                            border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: modelData
                                color: FiatLuxTheme.primaryText
                                font.pixelSize: Theme.fontSizeMedium
                                font.family: FiatLuxTheme.serif
                                font.italic: true
                            }
                        }
                    }
                }
            }
        }
}
