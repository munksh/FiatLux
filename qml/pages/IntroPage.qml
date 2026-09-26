import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0
import ".."
import "../components"

// Shown once on first start, and again whenever `version` is raised because
// the way the app works has changed. Skip and "start metering" both count as
// seen. It can be opened again from the About page.

Page {
    id: page
    allowedOrientations: Orientation.Portrait

    property int version: 1

    ConfigurationValue {
        id: cfgIntro
        key: "/apps/harbour-fiatlux/introVersion"
        defaultValue: 0
    }

    function done() {
        cfgIntro.value = page.version
        pageStack.pop()
    }

    function paint() { FiatLuxTheme.applyPalette(page) }
    Component.onCompleted: paint()
    Connections {
        target: FiatLuxTheme
        onAmbientChanged: page.paint()
    }

    Rectangle {
        anchors.fill: parent
        z: -1
        visible: !FiatLuxTheme.ambient
        gradient: Gradient {
            GradientStop { position: 0.0; color: FiatLuxTheme.backgroundHigh }
            GradientStop { position: 1.0; color: FiatLuxTheme.backgroundLow }
        }
    }

    readonly property var steps: [
        { title: qsTr("point"),
          text: qsTr("Point the phone at what you are photographing and press measure. Lux reads it the way a reflected meter does: whatever it sees, it takes for mid-grey. Tap the viewfinder to meter one spot; press and hold to go back to the whole frame.") },
        { title: qsTr("choose"),
          text: qsTr("Every pair in the row gives the same exposure. Swipe to the aperture you want. The cover shows the pair you chose.") },
        { title: qsTr("your cameras"),
          text: qsTr("Add your cameras from Cameras in the pull-down menu, with the speeds and apertures they really have. Lux then only suggests settings you can set.") },
        { title: qsTr("load film"),
          text: qsTr("Load a film into a camera and choose the speed you shoot it at. That speed then stays with the camera until the next film. Quick Meter is for everything else, with any ISO you like.") },
        { title: qsTr("log shot"),
          text: qsTr("Log shot keeps the frame with its settings burnt in, and counts it. Measuring never uses up a frame.") }
    ]

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: content.height + Theme.paddingLarge

        Column {
            id: content
            width: parent.width
            spacing: Theme.paddingLarge

            Item {
                width: parent.width
                height: Math.max(head.height, skip.y + skip.height)

                PageHead {
                    id: head
                    title: qsTr("welcome")
                    subtitle: "fiat lux"
                }

                BackgroundItem {
                    id: skip
                    anchors.left: parent.left
                    y: Math.max(0, FiatLuxTheme.statusRowCenter - height / 2)
                    width: skipText.implicitWidth + Theme.horizontalPageMargin * 2
                    height: Theme.itemSizeSmall
                    highlightedColor: FiatLuxTheme.highlightWash
                    onClicked: page.done()
                    Text {
                        id: skipText
                        anchors.centerIn: parent
                        text: qsTr("skip")
                        color: FiatLuxTheme.accent
                        font.pixelSize: Theme.fontSizeMedium
                        font.family: FiatLuxTheme.serif
                        font.italic: true
                    }
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeMedium
                font.family: FiatLuxTheme.serif
                color: FiatLuxTheme.primaryText
                text: qsTr("A light meter for cameras that do not have one of their own. Five things are worth knowing.")
            }

            Repeater {
                model: page.steps
                delegate: Row {
                    x: Theme.horizontalPageMargin
                    width: content.width - Theme.horizontalPageMargin * 2
                    spacing: Theme.paddingLarge

                    Label {
                        id: number
                        width: Theme.itemSizeExtraSmall
                        horizontalAlignment: Text.AlignRight
                        text: (index + 1).toString()
                        font.pixelSize: Theme.fontSizeExtraLarge
                        font.family: FiatLuxTheme.serif
                        color: FiatLuxTheme.accent
                    }

                    Column {
                        width: parent.width - number.width - parent.spacing
                        spacing: Theme.paddingSmall
                        Label {
                            text: modelData.title
                            font.pixelSize: Theme.fontSizeMedium
                            font.family: FiatLuxTheme.serif
                            font.italic: true
                            color: FiatLuxTheme.primaryText
                        }
                        Label {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: modelData.text
                            font.pixelSize: Theme.fontSizeExtraSmall
                            color: FiatLuxTheme.secondaryText
                        }
                    }
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: FiatLuxTheme.secondaryText
                text: qsTr("Lux meters through the camera with RAWfish's Camera2 helper, so RAWfish has to be installed. It has only been tested on the Jolla Phone (2026). If it disagrees with a meter you trust, set the difference under Calibrate.")
            }

            BackgroundItem {
                id: startBtn
                width: parent.width
                height: Theme.itemSizeLarge
                onClicked: page.done()
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    height: Theme.itemSizeMedium
                    radius: Theme.paddingLarge
                    color: startBtn.highlighted ? Qt.darker(FiatLuxTheme.accent, 1.2) : FiatLuxTheme.accent
                    Text {
                        anchors.centerIn: parent
                        text: qsTr("start metering")
                        color: FiatLuxTheme.onAccent
                        font.pixelSize: Theme.fontSizeMedium
                        font.family: FiatLuxTheme.serif
                        font.italic: true
                        font.bold: true
                    }
                }
            }

            Item { width: 1; height: Theme.paddingLarge }
        }

        VerticalScrollDecorator { }
    }
}
