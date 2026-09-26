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

    property int version: 2

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

    PaperBackground { }

    readonly property var steps: [
        { title: qsTr("point"),
          text: qsTr("Point the phone at what you are photographing and press measure. Lux reads it the way a reflected meter does: whatever it sees, it takes for mid-grey. Tap the viewfinder to meter one spot; press and hold to go back to the whole frame.") },
        { title: qsTr("choose"),
          text: qsTr("The dial pairs each aperture with the speeds your camera really has. Drag it to the aperture you want; the nearest speed is picked, and the line under the dial says how far off it is. Tap another speed to go over or under on purpose. The cover shows the pair you chose.") },
        { title: qsTr("your cameras"),
          text: qsTr("Add your cameras from Cameras in the pull-down menu, with the speeds and apertures they really have. Lux then only suggests settings you can set. Switch camera from the line under the dial.") },
        { title: qsTr("load film"),
          text: qsTr("Load a film into a camera and choose the speed you shoot it at. That speed then stays with the camera until the next film. Quick Meter is for everything else, with any ISO you like.") },
        { title: qsTr("log shot"),
          text: qsTr("Log shot takes a photo with the settings burnt in, keeps it in Pictures/FiatLux, and counts the frame. Measuring never uses up a frame.") }
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

                LinkText {
                    id: skip
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.horizontalPageMargin - Theme.paddingSmall
                    y: Math.max(0, FiatLuxTheme.statusRowCenter - height / 2)
                    text: qsTr("skip")
                    underline: false
                    italic: true
                    fontSize: Theme.fontSizeMedium
                    onClicked: page.done()
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
                text: qsTr("Lux meters through the phone's own camera; nothing else needs to be installed. It has only been tested on the Jolla Phone (2026). If it disagrees with a meter you trust, set the difference under Calibrate.")
            }

            FiatButton {
                text: qsTr("start metering")
                onClicked: page.done()
            }

            Item { width: 1; height: Theme.paddingLarge }
        }

        VerticalScrollDecorator { }
    }
}
