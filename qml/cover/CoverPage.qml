import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0
import ".." 1.0
import "../components"

CoverBackground {
    id: cover

    // ---- state ----

    ConfigurationValue {
        id: lastAperture
        key: "/apps/harbour-fiatlux/lastAperture"
        defaultValue: ""
    }
    ConfigurationValue {
        id: lastSpeed
        key: "/apps/harbour-fiatlux/lastSpeed"
        defaultValue: ""
    }

    readonly property bool hasReading:
        lastAperture.value !== undefined && lastAperture.value !== "" &&
        lastSpeed.value !== undefined && lastSpeed.value !== ""

    // ---- paper ----

    PaperBackground { }

    // ---- wordmark ----

    Label {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: FiatLuxTheme.coverWordmarkTop
        text: "fiat lux"
        color: FiatLuxTheme.secondaryText
        font.pixelSize: Theme.fontSizeTiny
        font.family: FiatLuxTheme.serif
        font.italic: true
    }

    // ---- figure ----

    Column {
        visible: cover.hasReading
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: FiatLuxTheme.coverSideMargin
        anchors.rightMargin: FiatLuxTheme.coverSideMargin
        anchors.topMargin: cover.height * FiatLuxTheme.coverFigureFraction
        spacing: 0

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            truncationMode: TruncationMode.Fade
            text: "f/" + lastAperture.value
            color: FiatLuxTheme.accent
            font.pixelSize: FiatLuxTheme.coverFigureSize
            font.family: FiatLuxTheme.serif
        }

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            truncationMode: TruncationMode.Fade
            text: lastSpeed.value
            color: FiatLuxTheme.accent
            font.pixelSize: FiatLuxTheme.coverFigureSize
            font.family: FiatLuxTheme.serif
        }
    }


    Label {
        visible: !cover.hasReading
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: FiatLuxTheme.coverSideMargin
        anchors.rightMargin: FiatLuxTheme.coverSideMargin
        anchors.topMargin: cover.height * FiatLuxTheme.coverFigureFraction
        horizontalAlignment: Text.AlignHCenter
        text: qsTr("not metered")
        color: FiatLuxTheme.secondaryText
        font.pixelSize: Theme.fontSizeExtraSmall
    }
}