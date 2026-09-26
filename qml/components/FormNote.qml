import QtQuick 2.0
import Sailfish.Silica 1.0
import ".."

// A line of help under a form row, indented like Silica's own descriptions.

Label {
    x: Theme.horizontalPageMargin
    width: (parent ? parent.width : 0) - Theme.horizontalPageMargin * 2
    wrapMode: Text.Wrap
    font.pixelSize: Theme.fontSizeExtraSmall
    color: FiatLuxTheme.secondaryText
}
