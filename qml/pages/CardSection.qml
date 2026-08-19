import QtQuick 2.0
import Sailfish.Silica 1.0
import ".." 1.0

// A surface card with an italic title and a column of child content.
// Children declared inside are reparented into the inner column.
Item {
    id: root
    property string title: ""
    default property alias content: inner.data

    x: Theme.horizontalPageMargin
    width: parent.width - 2 * Theme.horizontalPageMargin
    height: card.height

    Rectangle {
        id: card
        width: parent.width
        height: inner.height + Theme.paddingLarge * 2
        radius: Theme.paddingLarge * 1.5
        color: FiatLuxTheme.surface
        border.color: FiatLuxTheme.rim
        border.width: 1

        Column {
            id: inner
            x: Theme.paddingLarge
            y: Theme.paddingLarge
            width: parent.width - 2 * Theme.paddingLarge
            spacing: Theme.paddingMedium

            Text {
                visible: root.title.length > 0
                text: root.title
                color: FiatLuxTheme.secondaryText
                font.pixelSize: Theme.fontSizeSmall
                font.family: FiatLuxTheme.serif
                font.italic: true
            }
        }
    }
}
