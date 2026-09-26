import QtQuick 2.0
import Sailfish.Silica 1.0
import "../Gear.js" as Gear
import ".."

// The exposure plate from the back of a TLR: a framed table, a caption along
// the top, the values in groups. Every value has a cell of its own, so the
// eye can count along a row, and a chosen value is in the accent with a bar
// under it.
//
// Rows hold up to four cells and are spread evenly (seven values are a row of
// four and a row of three, not four and a lonely three-quarters), and every
// row runs the full width, so a row of three has wider cells than a row of
// four.

Rectangle {
    id: plate

    // [{ title: "fast", values: ["1/60", ...] }, ...]
    property var groups: []
    property var selected: []
    property var fresh: []            // just added by hand: shaded
    property string prefix: ""        // "f/" for apertures
    property string captionLeft: ""
    property string captionRight: ""

    signal toggled(string value)

    x: Theme.horizontalPageMargin
    width: (parent ? parent.width : 0) - Theme.horizontalPageMargin * 2
    height: body.height + Theme.paddingMedium * 2
    radius: Theme.paddingSmall
    color: Theme.rgba(FiatLuxTheme.card, 0.35)
    border.color: FiatLuxTheme.primaryText
    border.width: Math.max(2, Math.round(Theme.paddingSmall / 3))

    readonly property real cellHeight: Theme.itemSizeSmall
    readonly property real hairline: Math.max(1, Math.round(Theme.paddingSmall / 6))

    Column {
        id: body
        x: Theme.paddingMedium
        y: Theme.paddingMedium
        width: parent.width - Theme.paddingMedium * 2

        // ---- the caption: whose plate, and what it lists ----
        Item {
            visible: plate.captionLeft !== "" || plate.captionRight !== ""
            width: parent.width
            height: visible ? captionL.height + Theme.paddingSmall * 2 : 0

            Label {
                id: captionL
                anchors.left: parent.left
                anchors.leftMargin: Theme.paddingSmall
                width: parent.width / 2
                truncationMode: TruncationMode.Fade
                text: plate.captionLeft
                color: FiatLuxTheme.secondaryText
                font.pixelSize: Theme.fontSizeExtraSmall
                font.family: FiatLuxTheme.serif
                font.italic: true
            }
            Label {
                anchors.right: parent.right
                anchors.rightMargin: Theme.paddingSmall
                width: parent.width / 2 - Theme.paddingSmall
                horizontalAlignment: Text.AlignRight
                truncationMode: TruncationMode.Fade
                text: plate.captionRight
                color: FiatLuxTheme.secondaryText
                font.pixelSize: Theme.fontSizeExtraSmall
                font.family: FiatLuxTheme.serif
                font.italic: true
            }
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: plate.hairline
                color: FiatLuxTheme.primaryText
            }
        }

        Repeater {
            model: plate.groups
            delegate: Column {
                id: group
                width: body.width
                readonly property var rows: Gear.rowsFor(modelData.values)

                Label {
                    x: Theme.paddingSmall
                    height: implicitHeight + Theme.paddingMedium
                    verticalAlignment: Text.AlignBottom
                    text: modelData.title.toUpperCase()
                    color: FiatLuxTheme.secondaryText
                    font.pixelSize: Theme.fontSizeTiny
                    font.letterSpacing: Theme.paddingSmall / 3
                }

                Repeater {
                    model: group.rows
                    delegate: Item {
                        id: rowItem
                        width: group.width
                        height: plate.cellHeight
                        readonly property var cells: modelData

                        Rectangle {
                            width: parent.width
                            height: plate.hairline
                            color: FiatLuxTheme.innerBorder
                            opacity: 0.5
                        }

                        Row {
                            anchors.fill: parent
                            Repeater {
                                model: rowItem.cells
                                delegate: BackgroundItem {
                                    id: cell
                                    width: rowItem.width / rowItem.cells.length
                                    height: rowItem.height
                                    highlightedColor: FiatLuxTheme.highlightWash
                                    readonly property bool on: plate.selected.indexOf(modelData) !== -1
                                    onClicked: plate.toggled(modelData)

                                    Rectangle {
                                        anchors.fill: parent
                                        visible: plate.fresh.indexOf(modelData) !== -1
                                        color: FiatLuxTheme.highlightWash
                                    }
                                    Rectangle {
                                        visible: index > 0
                                        width: plate.hairline
                                        height: parent.height
                                        color: FiatLuxTheme.innerBorder
                                    }
                                    Label {
                                        anchors.centerIn: parent
                                        text: plate.prefix + modelData
                                        color: cell.on ? FiatLuxTheme.accent : FiatLuxTheme.secondaryText
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.bold: cell.on
                                    }
                                    Rectangle {
                                        visible: cell.on
                                        anchors.bottom: parent.bottom
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: parent.width / 2
                                        height: Math.max(3, Theme.paddingSmall / 2)
                                        color: FiatLuxTheme.accent
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
