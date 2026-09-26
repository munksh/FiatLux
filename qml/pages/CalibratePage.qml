import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0
import se.munkstolen.fiatlux 1.0
import ".." 1.0
import "../components"

// One number, found once against a meter you trust, and then left alone.
//
// The camera meters like any reflected meter: it reads what it is pointed at
// as mid-grey. What it does not know is how far its own idea of mid-grey sits
// from a hand-held meter's. That gap is a constant number of stops, and this
// page is where it is set.
//
// On the Jolla Phone (2026) it is +4: against a trusted reflected meter, in
// four scenes from EV 5 to EV 11, the camera read 3.7 to 4.4 stops low.

Page {
    id: page
    allowedOrientations: Orientation.Portrait

    ConfigurationValue {
        id: cfgCalibration
        key: "/apps/harbour-fiatlux/evCalibrationReflected"
        defaultValue: 4.0
    }

    readonly property real offset: {
        var v = cfgCalibration.value
        return (v === undefined || v === null) ? 4.0 : v
    }

    readonly property real rawEv: meter.metered ? meter.ev100 : NaN
    readonly property real correctedEv: isNaN(rawEv) ? NaN : rawEv + page.offset

    function nudge(stops) {
        var v = page.offset + stops
        if (v < -8) v = -8
        if (v > 8) v = 8
        // Snap to thirds, or 0.30000000000000004 ends up on screen.
        cfgCalibration.value = Math.round(v * 3) / 3
    }

    function formatSeconds(t) {
        if (!(t > 0)) return "-"
        if (t < 1) return "1/" + Math.round(1 / t)
        return t.toFixed(1) + "\""
    }

    function paint() { FiatLuxTheme.applyPalette(page) }
    Component.onCompleted: paint()
    Connections {
        target: FiatLuxTheme
        onAmbientChanged: page.paint()
    }

    // Polled: on Sailfish the change signal of Qt.application.state does not
    // reliably arrive, and a binding on it latches.
    property int appState: Qt.ApplicationActive
    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: page.appState = Qt.application.state
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

            // ---- what the camera sees: the same square as the meter ----
            Rectangle {
                width: parent.width
                height: width
                color: FiatLuxTheme.viewfinderBg
                clip: true

                Camera2Meter {
                    id: meter
                    anchors.fill: parent
                    fill: true
                    photos: false
                    active: page.status === PageStatus.Active
                            && page.appState === Qt.ApplicationActive
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: if (!meter.hasFrame) meter.restart()
                }

                Text {
                    anchors.centerIn: parent
                    width: parent.width - Theme.horizontalPageMargin * 2
                    visible: !meter.hasFrame
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    text: meter.errorString !== "" ? meter.errorString : qsTr("waking the camera")
                    font.pixelSize: meter.errorString !== "" ? Theme.fontSizeExtraSmall : Theme.fontSizeSmall
                    font.family: meter.errorString !== "" ? Theme.fontFamily : FiatLuxTheme.serif
                    font.italic: meter.errorString === ""
                    color: FiatLuxTheme.viewfinderText
                    opacity: 0.75
                }
            }

            // ---- the live reading ----
            Column {
                width: parent.width
                spacing: Theme.paddingSmall

                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: meter.metered
                          ? "f/" + meter.aperture.toFixed(2) + "  ·  "
                            + page.formatSeconds(meter.exposureTime) + "  ·  ISO " + meter.iso
                          : qsTr("no reading")
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
                    text: isNaN(page.rawEv) ? "" : qsTr("the camera says EV %1").arg(page.rawEv.toFixed(1))
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: FiatLuxTheme.secondaryText
                }
            }

            // ---- the constant: −⅓  +4.00 stops  +⅓ ----
            Item {
                width: parent.width
                height: Theme.itemSizeMedium

                LinkText {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.horizontalPageMargin - Theme.paddingSmall
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.itemSizeMedium
                    text: "−⅓"
                    underline: false
                    fontSize: Theme.fontSizeLarge
                    onClicked: page.nudge(-1/3)
                }

                Label {
                    anchors.centerIn: parent
                    text: (page.offset > 0 ? "+" : "") + page.offset.toFixed(2) + " " + qsTr("stops")
                    font.pixelSize: Theme.fontSizeLarge
                    font.family: FiatLuxTheme.serif
                    color: FiatLuxTheme.accent
                }

                LinkText {
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.horizontalPageMargin - Theme.paddingSmall
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.itemSizeMedium
                    horizontalAlignment: Text.AlignRight
                    text: "+⅓"
                    underline: false
                    fontSize: Theme.fontSizeLarge
                    onClicked: page.nudge(1/3)
                }
            }

            Slider {
                width: parent.width
                minimumValue: -8
                maximumValue: 8
                stepSize: 1/3
                value: page.offset
                valueText: ""
                onValueChanged: {
                    var v = Math.round(value * 3) / 3
                    if (Math.abs(v - page.offset) > 0.001) cfgCalibration.value = v
                }
            }

            // ---- how ----

            FormNote {
                text: qsTr("Fill the frame with a matte mid-grey surface in even light. Meter the same surface with a reflected meter you trust, set to the same film speed, and compare its EV with the one above.\n\nIf this phone reads higher than your meter, it thinks the scene is brighter than it is, and the number above should come down by the difference.")
            }

            LinkText {
                x: Theme.horizontalPageMargin - Theme.paddingSmall
                text: qsTr("reset to +4.00, measured on the Jolla Phone (2026)")
                onClicked: cfgCalibration.value = 4.0
            }

            Item { width: 1; height: Theme.paddingMedium }
        }

        VerticalScrollDecorator { }
    }
}
