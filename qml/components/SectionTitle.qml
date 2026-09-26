import QtQuick 2.0
import Sailfish.Silica 1.0
import ".."

// A small italic heading between groups of form rows: "film", "shoot at".
// What the card titles used to say, without the card.

Label {
    x: Theme.horizontalPageMargin
    width: (parent ? parent.width : 0) - Theme.horizontalPageMargin * 2
    height: implicitHeight + Theme.paddingMedium
    verticalAlignment: Text.AlignBottom
    color: FiatLuxTheme.secondaryText
    font.pixelSize: Theme.fontSizeSmall
    font.family: FiatLuxTheme.serif
    font.italic: true
}
