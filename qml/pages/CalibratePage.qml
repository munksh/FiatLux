import QtQuick 2.0
import Sailfish.Silica 1.0
import QtSensors 5.2
import Nemo.Configuration 1.0
import ".." 1.0
import "../components"

// One number, measured once, and then never thought about again.
//
// The phone's ambient light sensor is a bare photodiode behind the screen
// glass, not a photographic meter. It reads consistently, but it does not read
// correctly, and the difference is a constant number of stops. This page is
// where that constant is found.
//
// Measured on the Jolla Phone (2026) against a calibrated reflected meter,
// using a matte mid-grey sheet, at EV 7, EV 9 and EV 12: the sensor read three
// stops bright every time. Hence the default. Three readings five stops apart
// agreeing to the tenth is what makes it a constant rather than an average.
//
// Readings taken with the subject lying flat -- on a floor, under a table --
// came out four to five stops instead. Not the sensor: the person doing the
// metering was shading the subject from the reflected meter while the phone,
// facing up, saw the light unobstructed. Meter things standing up.

Page {
    id: page
    allowedOrientations: Orientation.Portrait

    ConfigurationValue {
        id: cfgCalibration
        key: "/apps/harbour-fiatlux/evCalibration"
        defaultValue: -3.0
    }

    property real lux: -1

    // What the sensor says, before anything is done to it.
    readonly property real rawEv: lux > 0 ? Math.log(lux / 2.5) / Math.LN2 : NaN

    // What the meter will actually use.
    readonly property real correctedEv: isNaN(rawEv) ? NaN : rawEv + cfgCalibration.value

    function nudge(stops) {
        var v = cfgCalibration.value + stops
        if (v < -8) v = -8
        if (v > 8) v = 8
        // Snap to thirds. Photographers think in thirds; floating point does
        // not, and 0.30000000000000004 on screen would be its own bug report.
        cfgCalibration.value = Math.round(v * 3) / 3
    }

    LightSensor {
        active: Qt.application.state === Qt.ApplicationActive
        onReadingChanged: page.lux = reading.illuminance
    }

    PaperBackground { }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: content.height + Theme.paddingLarge

        Column {
            id: content
            width: parent.width
            spacing: Theme.paddingMedium

            PageHead {
                title: qsTr("calibrate")
                subtitle: "fiat lux"
            }

            // ---- the live reading ----
            //
            // Both numbers, always. Seeing the raw value move while the
            // corrected one sits where you put it is the whole explanation of
            // what this page does, and it needs no paragraph.
            Rectangle {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                height: readings.height + Theme.paddingLarge * 2
                radius: FiatLuxTheme.cardRadius
                color: FiatLuxTheme.card
                border.color: FiatLuxTheme.cardBorder
                border.width: FiatLuxTheme.cardBorderWidth

                Column {
                    id: readings
                    anchors.centerIn: parent
                    width: parent.width - Theme.paddingLarge * 2
                    spacing: Theme.paddingSmall

                    Label {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: page.lux > 0 ? Math.round(page.lux) + " lx" : qsTr("no reading")
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: FiatLuxTheme.secondaryText
                    }

                    Label {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: isNaN(page.correctedEv) ? "—" : "EV " + page.correctedEv.toFixed(1)
                        font.pixelSize: Theme.fontSizeExtraLarge
                        font.family: FiatLuxTheme.serif
                        color: FiatLuxTheme.primaryText
                    }

                    Label {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: isNaN(page.rawEv)
                              ? ""
                              : qsTr("sensor says EV %1").arg(page.rawEv.toFixed(1))
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: FiatLuxTheme.secondaryText
                    }
                }
            }

            // ---- the constant ----
            Item {
                width: parent.width
                height: Math.max(minusBtn.height, offsetLabel.height)

                BackgroundItem {
                    id: minusBtn
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    width: minusBg.width
                    height: minusBg.height
                    highlightedColor: FiatLuxTheme.highlightWash
                    onClicked: page.nudge(-1/3)
                    Rectangle {
                        id: minusBg
                        radius: height / 2
                        width: Theme.itemSizeSmall
                        height: Theme.itemSizeExtraSmall
                        color: minusBtn.highlighted ? FiatLuxTheme.pillFillActive : FiatLuxTheme.pillFill
                        border.color: FiatLuxTheme.pillBorder
                        border.width: 1
                        Label {
                            anchors.centerIn: parent
                            text: "−⅓"
                            font.pixelSize: Theme.fontSizeSmall
                            color: FiatLuxTheme.primaryText
                        }
                    }
                }

                Label {
                    id: offsetLabel
                    anchors.centerIn: parent
                    text: (cfgCalibration.value > 0 ? "+" : "")
                          + cfgCalibration.value.toFixed(2) + " " + qsTr("stops")
                    font.pixelSize: Theme.fontSizeLarge
                    font.family: FiatLuxTheme.serif
                    color: FiatLuxTheme.accent
                }

                BackgroundItem {
                    id: plusBtn
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    width: plusBg.width
                    height: plusBg.height
                    highlightedColor: FiatLuxTheme.highlightWash
                    onClicked: page.nudge(1/3)
                    Rectangle {
                        id: plusBg
                        radius: height / 2
                        width: Theme.itemSizeSmall
                        height: Theme.itemSizeExtraSmall
                        color: plusBtn.highlighted ? FiatLuxTheme.pillFillActive : FiatLuxTheme.pillFill
                        border.color: FiatLuxTheme.pillBorder
                        border.width: 1
                        Label {
                            anchors.centerIn: parent
                            text: "+⅓"
                            font.pixelSize: Theme.fontSizeSmall
                            color: FiatLuxTheme.primaryText
                        }
                    }
                }
            }

            Slider {
                width: parent.width
                minimumValue: -8
                maximumValue: 8
                stepSize: 1/3
                value: cfgCalibration.value
                valueText: ""
                onValueChanged: {
                    var v = Math.round(value * 3) / 3
                    if (Math.abs(v - cfgCalibration.value) > 0.001) cfgCalibration.value = v
                }
            }

            // ---- how ----

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: FiatLuxTheme.secondaryText
                text: qsTr("Hold a matte mid-grey surface upright, facing the light. Meter it with a meter you trust, set to the same film speed and the same aperture. Stand this phone beside it, screen facing the same way, and read the EV above.\n\nCount the stops between the two shutter speeds. If this phone suggests the faster one, it thinks the scene is brighter than it is, and the number below should be negative by that many stops.")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: FiatLuxTheme.secondaryText
                text: qsTr("Do it in daylight, and do it with the subject standing up. Leaning over something lying flat puts your own shadow on it, and then the two meters are looking at different amounts of light rather than disagreeing about the same light.")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: FiatLuxTheme.outOfRange
                text: qsTr("This holds for daylight only. A bare photodiode sees further into the infrared than film does, and tungsten and many LEDs are full of it, so under a lamp the reading runs bright by an amount that depends on the lamp. No single number corrects that.")
            }

            Item { width: 1; height: Theme.paddingMedium }

            BackgroundItem {
                width: parent.width
                height: Theme.itemSizeSmall
                highlightedColor: FiatLuxTheme.highlightWash
                onClicked: cfgCalibration.value = -3.0
                Label {
                    x: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Reset to −3.00, measured on this phone")
                    font.pixelSize: Theme.fontSizeSmall
                    color: FiatLuxTheme.accent
                }
            }
        }

        VerticalScrollDecorator { }
    }
}
