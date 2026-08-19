import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0
import ".."
import "../components"

// The cover is a reading, not a control. You metered, you liked it, you put
// the phone down -- and now you want to see it again without opening anything.
//
// The last reading is shared with the meter through dconf rather than through
// a shared object. The cover is loaded by URL and cannot see ids declared in
// the app's root QML, so the two need something neither has to know about.
// A dconf key also has the useful side effect of surviving a restart: put the
// phone down, pick it up tomorrow, and the cover still says what you settled
// on. A context property would not do that.
//
// Nothing here is tappable. No CoverAction to re-meter: metering means aiming
// the camera at something, and you cannot aim a phone you are reading.

CoverBackground {
    id: cover

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
    ConfigurationValue {
        id: lastCamera
        key: "/apps/harbour-fiatlux/lastCamera"
        defaultValue: ""
    }
    ConfigurationValue {
        id: lastIso
        key: "/apps/harbour-fiatlux/lastIso"
        defaultValue: 0
    }
    ConfigurationValue {
        id: lastFilm
        key: "/apps/harbour-fiatlux/lastFilm"
        defaultValue: ""
    }

    // Empty until the meter has written something. Written defensively:
    // a dconf value can read back undefined before the key exists.
    readonly property bool hasReading:
        lastAperture.value !== undefined && lastAperture.value !== "" &&
        lastSpeed.value !== undefined && lastSpeed.value !== ""

    PaperBackground { }

    // ---- no reading yet: the dome, and nothing claimed ----

    Canvas {
        id: dome
        visible: !cover.hasReading
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -Theme.paddingLarge
        width: 96
        height: 58

        // Canvas does not repaint when a colour it reads changes, so the
        // colours have to be properties it can watch.
        property color domeColor: FiatLuxTheme.accent
        property color baseColor: Theme.rgba(FiatLuxTheme.accent, 0.55)
        property color glintColor: Theme.rgba(FiatLuxTheme.markOn(FiatLuxTheme.accent), 0.35)

        onDomeColorChanged: requestPaint()
        onBaseColorChanged: requestPaint()
        onGlintColorChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            ctx.beginPath()
            ctx.arc(48, 58, 48, Math.PI, 0)
            ctx.fillStyle = dome.domeColor
            ctx.fill()

            ctx.beginPath()
            ctx.ellipse(0, 50, 96, 16)
            ctx.fillStyle = dome.baseColor
            ctx.fill()

            ctx.beginPath()
            ctx.arc(34, 30, 11, Math.PI * 1.1, Math.PI * 1.75)
            ctx.strokeStyle = dome.glintColor
            ctx.lineWidth = 4
            ctx.lineCap = "round"
            ctx.stroke()
        }
    }

    // ---- a reading ----
    //
    // The pair is the point, so the pair is the only large thing. The camera
    // above it and the film below it are context: they answer "of what?" and
    // "at what speed?", and neither is what you picked up the phone to read.

    Column {
        visible: cover.hasReading
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -Theme.paddingMedium
        width: parent.width - Theme.paddingMedium * 2
        spacing: Theme.paddingSmall

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            truncationMode: TruncationMode.Fade
            text: lastCamera.value === undefined ? "" : lastCamera.value
            font.pixelSize: Theme.fontSizeExtraSmall
            color: FiatLuxTheme.secondaryText
        }

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            truncationMode: TruncationMode.Fade
            // The interpunct is doing real work: it says these two belong
            // together and are read as one setting, not as two numbers.
            text: "f/" + lastAperture.value + "  ·  " + lastSpeed.value
            font.pixelSize: Theme.fontSizeLarge
            font.family: FiatLuxTheme.serif
            color: FiatLuxTheme.primaryText
        }

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            truncationMode: TruncationMode.Fade
            font.pixelSize: Theme.fontSizeExtraSmall
            color: FiatLuxTheme.secondaryText
            text: {
                var iso = lastIso.value === undefined ? 0 : lastIso.value
                var film = lastFilm.value === undefined ? "" : lastFilm.value
                var parts = []
                if (iso > 0) parts.push("ISO " + iso)
                if (film !== "") parts.push(film)
                return parts.join("  ·  ")
            }
        }
    }

    // ---- the wordmark ----
    //
    // Lowercase, serif, italic, same as everywhere else in the family.

    Label {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.paddingLarge
        text: "fiat lux"
        color: FiatLuxTheme.primaryText
        font.pixelSize: Theme.fontSizeSmall
        font.family: FiatLuxTheme.serif
        font.italic: true
    }
}
