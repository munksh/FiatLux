import QtQuick 2.0
import Sailfish.Silica 1.0
import ".."

// The paper. One line per page, and the whole reason Fiat colours look like
// anything at all.
//
// Under an ambience this draws NOTHING. `visible` is false and the wallpaper
// is the background -- that is the entire idea of ambience-first, and if you
// ever find yourself deleting that condition you have just cancelled the
// ambience for the sake of one screen.
//
// A vertical Gradient and not a radial one: QML's built-in Gradient is linear
// only, and pulling in QtGraphicalEffects for a background is not worth it.
//
// z: -1 so it stays behind the page's content whether it is declared above or
// below it. That means you can paste the line at the top of a Page without
// reading the rest of the file first.

Rectangle {
    anchors.fill: parent
    z: -1
    visible: !FiatLuxTheme.ambient
    gradient: Gradient {
        GradientStop { position: 0.0; color: FiatLuxTheme.backgroundHigh }
        GradientStop { position: 1.0; color: FiatLuxTheme.backgroundLow }
    }
}