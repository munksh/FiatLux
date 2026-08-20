import QtQuick 2.0
import Sailfish.Silica 1.0
import QtMultimedia 5.0
import QtSensors 5.2
import Nemo.Configuration 1.0
import "../Storage.js" as Storage
import ".." 1.0
import "../components"

Page {
    id: page
    allowedOrientations: Orientation.Portrait

    property int rollId: -1
    property int presetCameraId: -1
    property string sourceLabel: "Quick Meter"
    property int cameraType: 0
    property string mount: ""
    property string bodySpeeds: ""
    property int iso: 400
    property bool isoLocked: false
    property var compatLenses: []
    property int lensIndex: 0
    property string lens: ""
    property var apertures: []
    property var shutterSpeeds: []
    property int scrollerGen: 0   // bump to force delegate rebuild
    property real ev: 8.0
    property bool evLocked: false
    property bool editingIso: false
    property int shotCount: 0

    // Fallback only. picturesPath() asks the platform first.
    property string picturesDir: "/home/defaultuser/Pictures"

    // Sensor rotation for the viewfinder. Try 0 / 90 / 180 / 270 / -90.
    property int viewfinderOrientation: 0

    // Light meter calibration, in stops. It lives in dconf so that the
    // calibrate page and the meter are looking at the same number and neither
    // owns it. -3 is what this phone measured against a trusted meter in
    // daylight, three times, five stops apart.
    ConfigurationValue {
        id: cfgCalibration
        key: "/apps/harbour-fiatlux/evCalibration"
        defaultValue: -3.0
    }
    readonly property real evCalibration: cfgCalibration.value
    property real lastLux: -1

    // ---- how the light is measured -------------------------------------
    //
    //   0  INCIDENT -- the ambient light sensor, next to the earpiece. It
    //      measures the light FALLING ON the phone: EV100 = log2(lux / C)
    //      with C = 250, so log2(lux / 2.5). Note where that sensor points --
    //      at YOU, not at the subject. Hold the phone at the subject facing
    //      the camera, the way you would hold a Sekonic with the dome on.
    //
    //   1  REFLECTED -- read back from the camera's own auto-exposure. It
    //      measures the light COMING OFF the subject, which is what a TTL
    //      meter does: EV100 = log2(N^2 / t) - log2(S / 100).
    //
    // They will not agree, and that is not a bug. A white wall and a black cat
    // reflect very different amounts of the same light.
    property int meterMode: 0
    property string meterNote: ""
    property string reflectedRaw: ""

    // Where the scroller lands after a measurement — handheld default 1/125 s.
    property real preferredSpeed: 1/125

    readonly property var defaultApertures: ["1","1.4","1.7","2","2.8","4","5.6","8","11","16","22"]
    readonly property var defaultSpeeds: ["1/1000","1/500","1/250","1/125","1/60","1/30","1/15","1/8","1/4","1/2","1\""]

    // ---- what the cover reads ------------------------------------------

    ConfigurationValue { id: cfgAperture; key: "/apps/harbour-fiatlux/lastAperture"; defaultValue: "" }
    ConfigurationValue { id: cfgSpeed;    key: "/apps/harbour-fiatlux/lastSpeed";    defaultValue: "" }
    ConfigurationValue { id: cfgCamera;   key: "/apps/harbour-fiatlux/lastCamera";   defaultValue: "" }
    ConfigurationValue { id: cfgIso;      key: "/apps/harbour-fiatlux/lastIso";      defaultValue: 0 }
    ConfigurationValue { id: cfgFilm;     key: "/apps/harbour-fiatlux/lastFilm";     defaultValue: "" }

    function publishReading() {
        // Nothing has been metered, so there is nothing to show. Publishing
        // the default 8.0 would put a number on the cover that no one chose.
        if (!evLocked) return
        cfgAperture.value = currentAperture()
        cfgSpeed.value = currentSpeed()
        cfgCamera.value = sourceLabel
        cfgIso.value = iso
        cfgFilm.value = rollId >= 0 ? sourceLabel : ""
    }

    Component.onCompleted: {
        if (rollId >= 0) loadRoll(rollId)
        else if (presetCameraId >= 0) loadCamera(presetCameraId)
        else loadQuick()
    }

    function loadQuick() {
        rollId = -1
        sourceLabel = "Quick Meter"
        cameraType = 0; mount = ""; bodySpeeds = ""
        iso = 400; isoLocked = false
        compatLenses = []; lensIndex = 0
        applyLens()
    }

    function loadCamera(id) {
        var c = Storage.getCamera(id)
        if (!c) { loadQuick(); return }
        sourceLabel = c.name
        cameraType = c.type
        mount = c.mount
        bodySpeeds = c.bodySpeeds || ""
        iso = 400; isoLocked = false
        compatLenses = Storage.lensesForMount(mount)
        lensIndex = 0
        applyLens()
    }

    function loadRoll(id) {
        var r = Storage.getRoll(id)
        if (!r) { loadQuick(); return }
        rollId = id
        sourceLabel = r.stockName !== "" ? r.stockName : (r.cameraName !== "" ? r.cameraName : "Roll")
        cameraType = r.cameraType ? r.cameraType : 0
        mount = r.mount || ""
        bodySpeeds = r.bodySpeeds || ""
        iso = r.pushIso; isoLocked = true
        compatLenses = mount.length > 0 ? Storage.lensesForMount(mount) : []
        lensIndex = 0
        for (var i = 0; i < compatLenses.length; i++)
            if (compatLenses[i].id === r.lensId) { lensIndex = i; break }
        applyLens()
        shotCount = Storage.shotCountForRoll(id)
    }

    function applyLens() {
        if (compatLenses.length > 0) {
            var l = compatLenses[lensIndex]
            lens = l.name
            // split() always returns a fresh array — no stale-reference problem
            apertures = (l.apertures || "").split(",")
            // Speed priority:
            //   1. Lens's own speeds (leaf / fixed lenses fill this in)
            //   2. Body speeds (SLR lenses leave lens speeds empty on purpose)
            //   3. Defaults (last resort — means data is incomplete)
            var lSpeeds  = l.speeds    && l.speeds.length    > 0 ? l.speeds    : ""
            var bSpeeds  = bodySpeeds  && bodySpeeds.length  > 0 ? bodySpeeds  : ""
            var srcSpeeds = lSpeeds.length > 0 ? lSpeeds
                          : bSpeeds.length > 0 ? bSpeeds
                          : null
            shutterSpeeds = srcSpeeds ? srcSpeeds.split(",") : defaultSpeeds.slice()
        } else {
            // No matching lens — use defaults
            // .slice() guarantees a new reference each time so QML sees the change
            lens = ""
            apertures = defaultApertures.slice()
            shutterSpeeds = defaultSpeeds.slice()
        }
        // Bump generation so ListView delegates fully rebuild
        scrollerGen++
    }

    function parseSpeed(s) {
        if (s === "B") return null
        if (s.indexOf("/") !== -1) {
            var p = s.split("/")
            return parseFloat(p[0]) / parseFloat(p[1])
        }
        return parseFloat(s.replace("\"", ""))
    }

    function calcShutterIndex(apertureIndex) {
        if (!apertures || apertures.length === 0 || !shutterSpeeds || shutterSpeeds.length === 0) return 0
        var f = parseFloat(apertures[apertureIndex])
        var speed = (f * f) / (Math.pow(2, ev) * (iso / 100))
        var closest = 0, diff = Infinity
        for (var i = 0; i < shutterSpeeds.length; i++) {
            var sv = parseSpeed(shutterSpeeds[i])
            if (sv === null) continue
            // Compare in stops, not raw seconds — otherwise long speeds
            // always look "further away" than short ones.
            var d = Math.abs(Math.log(sv / speed) / Math.LN2)
            if (d < diff) { diff = d; closest = i }
        }
        return closest
    }

    // Pick the aperture whose resulting shutter speed sits closest to
    // preferredSpeed, measured in stops.
    function suggestIndex() {
        if (!apertures || apertures.length === 0) return 0
        var best = 0, diff = Infinity
        for (var i = 0; i < apertures.length; i++) {
            var sv = parseSpeed(shutterSpeeds[calcShutterIndex(i)])
            if (sv === null || sv <= 0) continue
            var d = Math.abs(Math.log(sv / preferredSpeed) / Math.LN2)
            if (d < diff) { diff = d; best = i }
        }
        return best
    }

    // ---- the two measurements ------------------------------------------
    //
    // Both return EV at ISO 100, or NaN if they have nothing to say. NaN and
    // not 0: zero is a real exposure value (one second at f/1 on ISO 100) and
    // using it as "no reading" would silently meter a moonlit room.

    function measureIncident() {
        var lux = page.lastLux
        if (lux === undefined || !(lux > 0)) return NaN
        return Math.log(lux / 2.5) / Math.LN2
    }

    function measureReflected() {
        page.reflectedRaw = ""
        if (!page.cameraLive) return NaN

        var N = page.cam.exposure.aperture
        var t = page.cam.exposure.shutterSpeed
        var S = page.cam.exposure.iso

        // What the backend literally said, before anyone interprets it. This
        // goes on screen, not just in the log, because it is the one number in
        // the app that cannot be checked by looking at the result: a wrong EV
        // looks exactly like a dark room.
        page.reflectedRaw = "N " + N + " · t " + t + " · S " + S
        console.log("reflected —", page.reflectedRaw)

        if (!(N > 0) || !(t > 0) || !(S > 0)) return NaN

        // Unit guard.
        //
        // QtMultimedia documents shutterSpeed in SECONDS. The droid backend on
        // this phone appears to hand back the DENOMINATOR instead -- 60 for
        // 1/60 -- and that does not merely offset the reading, it INVERTS it:
        // log2(N^2 / t) becomes log2(N^2 * t_real), so the brighter the scene
        // the lower the EV comes out. Pointing at a window read darker than
        // pointing at the room, which is how this was caught.
        //
        // A phone viewfinder running its own auto-exposure never sits at a
        // whole second or longer -- it would be unwatchable. So any t at or
        // above 1 is a denominator, not an exposure time.
        var seconds = t >= 1 ? 1 / t : t

        return Math.log((N * N) / seconds) / Math.LN2 - Math.log(S / 100) / Math.LN2
    }

    function measure() {
        var v = NaN
        var note = ""

        if (meterMode === 1) {
            v = measureReflected()
            if (isNaN(v)) {
                // Not a failure worth hiding. The camera either reports its
                // exposure or it does not, and if it does not you should know
                // which number you are looking at.
                v = measureIncident()
                note = isNaN(v)
                    ? qsTr("camera reported no exposure, and no light sensor reading yet")
                    : qsTr("camera reported no exposure — fell back to the light sensor")
                if (page.reflectedRaw !== "") note += "\n" + page.reflectedRaw
            } else {
                note = qsTr("reflected · %1").arg(page.reflectedRaw)
            }
        } else {
            v = measureIncident()
            note = isNaN(v) ? qsTr("no light sensor reading yet")
                            : qsTr("incident · %1 lx").arg(Math.round(page.lastLux))
        }

        page.meterNote = note
        if (isNaN(v)) return

        ev = v + evCalibration
        evLocked = true
        exposureList.currentIndex = suggestIndex()
        publishReading()
    }

    function currentAperture() {
        if (!apertures || apertures.length === 0) return "-"
        return apertures[exposureList.currentIndex] || "-"
    }

    function currentSpeed() {
        if (!shutterSpeeds || shutterSpeeds.length === 0) return "-"
        return shutterSpeeds[calcShutterIndex(exposureList.currentIndex)] || "-"
    }

    // ---- logging a shot --------------------------------------------------
    //
    // One button, and it does the whole thing: grab the frame, save it, write
    // the row.
    //
    // The frame is grabbed from the VIEWFINDER ITEM, not from the camera's
    // still capture -- which means the HUD comes with it. The aperture, the
    // speed and the film speed are already drawn over the picture, so they are
    // burnt in for free and they are exactly what you were looking at when you
    // pressed. No compositing, no second code path that could disagree with
    // the screen.
    //
    // It is screen resolution and not the sensor's, and that is the right
    // trade. This is a note about what you metered. The photograph is on film.

    function picturesPath() {
        // Ask the platform; fall back to the hardcoded path if it will not say.
        try {
            if (typeof StandardPaths !== "undefined" && StandardPaths.pictures) {
                var p = "" + StandardPaths.pictures
                return p.indexOf("file://") === 0 ? p.substring(7) : p
            }
        } catch (e) { }
        return page.picturesDir
    }

    function logShot(photoPath) {
        if (rollId < 0) return
        Storage.addShot(rollId, new Date().toISOString(), ev,
                        currentAperture(), currentSpeed(), iso, photoPath || "")
        shotCount = Storage.shotCountForRoll(rollId)
    }

    function logShotWithFrame() {
        var name = "fiatlux-" + new Date().toISOString().replace(/[:.]/g, "-") + ".png"
        var path = picturesPath() + "/" + name

        var started = viewfinder.grabToImage(function(result) {
            // The flash fires AFTER the grab, never before. grabToImage
            // renders the next frame of this item, and the flash is a cream
            // rectangle at 0.6 opacity across the whole viewfinder -- start it
            // first and it is in the picture. That was the entire reason the
            // saved frames came out so much brighter than the scene.
            shotFlash.restart()

            if (result.saveToFile(path)) {
                page.logShot(path)
                page.meterNote = rollId >= 0
                    ? qsTr("logged · %1").arg(name)
                    : qsTr("saved %1 — open a roll to log it").arg(name)
            } else {
                page.logShot("")
                page.meterNote = qsTr("could not write to Pictures — logged without the frame")
            }
        })

        if (!started) {
            shotFlash.restart()
            page.logShot("")
            page.meterNote = qsTr("could not grab the frame — logged without it")
        }
    }

    // ---- the camera ------------------------------------------------------
    //
    // A Loader, and this is the whole fix.
    //
    // Sailfish's resource policy takes the camera away the moment the app goes
    // to its cover. Asking for it back does not work: the gstreamer pipeline
    // behind the Camera element is already dead, the element does not know it,
    // and a cameraState assignment lands on a corpse. No error, no return
    // value -- the viewfinder just stays black. Retrying harder does not help,
    // because there is nothing wrong with the request; the object is spent.
    //
    // So do not reuse it. The Loader DESTROYS the Camera when the app loses
    // focus and BUILDS A NEW ONE when it comes back, and a camera that was
    // created five milliseconds ago has no memory of anyone taking anything
    // from it. This is what Jolla's own camera app does.
    //
    // Everything that touches the camera goes through page.cam, which is null
    // while the Loader is inactive -- hence the guards everywhere.

    readonly property bool cameraWanted:
        page.status === PageStatus.Active && Qt.application.state === Qt.ApplicationActive

    readonly property var cam: cameraLoader.item

    readonly property bool cameraLive:
        cam !== null && cam !== undefined && cam.cameraStatus === Camera.ActiveStatus

    property string cameraNote: ""

    Loader {
        id: cameraLoader
        active: page.cameraWanted
        sourceComponent: Camera {
            captureMode: Camera.CaptureStillImage
            cameraState: Camera.ActiveState

            onCameraStatusChanged: {
                if (cameraStatus === Camera.ActiveStatus) {
                    page.cameraNote = ""
                    page.applyFocus()
                }
            }

            onError: {
                console.log("camera error:", errorCode, errorString)
                page.cameraNote = errorString
            }
        }
    }

    // Manual rebuild, for when it comes back wrong anyway. Tapping a black
    // viewfinder is what everyone tries first, so let it be the thing that
    // works. Setting `active` by hand breaks its binding, so the timer puts
    // the binding back rather than leaving it pinned.
    Timer {
        id: cameraReload
        interval: 250
        onTriggered: cameraLoader.active = Qt.binding(function() { return page.cameraWanted })
    }

    function reloadCamera() {
        page.cameraNote = ""
        cameraLoader.active = false
        cameraReload.restart()
    }

    // Only for the placeholder. A viewfinder that says "waking the camera"
    // forever is a lie; one that says which state it is in is a bug report you
    // can read without a laptop.
    function cameraStatusName() {
        if (page.cam === null || page.cam === undefined) return "no camera object"
        switch (page.cam.cameraStatus) {
        case Camera.UnavailableStatus: return "unavailable"
        case Camera.UnloadedStatus:    return "unloaded"
        case Camera.LoadingStatus:     return "loading"
        case Camera.UnloadingStatus:   return "unloading"
        case Camera.LoadedStatus:      return "loaded"
        case Camera.StandbyStatus:     return "standby"
        case Camera.StartingStatus:    return "starting"
        case Camera.StoppingStatus:    return "stopping"
        case Camera.ActiveStatus:      return "active"
        default:                       return "unknown"
        }
    }

    // ---- focus ----------------------------------------------------------
    //
    // Focus has to be requested AFTER the camera reaches ActiveStatus, not in
    // the declaration -- before that there is no device to ask, and the
    // assignment is quietly dropped. Every call is guarded, because which
    // modes exist is a property of the hardware and not of QtMultimedia.

    function applyFocus() {
        if (!page.cameraLive) return
        try {
            if (page.cam.focus.isFocusModeSupported(Camera.FocusContinuous)) {
                page.cam.focus.focusMode = Camera.FocusContinuous
            } else if (page.cam.focus.isFocusModeSupported(Camera.FocusAuto)) {
                page.cam.focus.focusMode = Camera.FocusAuto
                page.cam.searchAndLock()
            }
        } catch (e) { console.log("focus mode:", e) }
        try {
            if (page.cam.focus.isFocusPointModeSupported(Camera.FocusPointAuto)) {
                page.cam.focus.focusPointMode = Camera.FocusPointAuto
            }
        } catch (e) { console.log("focus point:", e) }
    }

    function refocus() {
        if (!page.cameraLive) return
        try {
            page.cam.unlock()
            if (page.cam.focus.isFocusModeSupported(Camera.FocusAuto))
                page.cam.focus.focusMode = Camera.FocusAuto
            page.cam.searchAndLock()
        } catch (e) { console.log("refocus:", e) }
    }

    LightSensor {
        id: lightSensor
        active: Qt.application.state === Qt.ApplicationActive
        onReadingChanged: page.lastLux = reading.illuminance
    }

    PaperBackground { }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: contentColumn.height

        // No backgroundColor here. Setting it paints the whole panel, which
        // dims the entire screen behind the menu -- it looks like the app
        // dropped out from under the drawer. Colour the items instead.
        PullDownMenu {
            highlightColor: FiatLuxTheme.accent

            MenuItem {
                text: FiatLuxTheme.ambient ? qsTr("fiat colours") : qsTr("Follow ambience")
                color: FiatLuxTheme.primaryText
                onClicked: FiatLuxTheme.setAmbient(!FiatLuxTheme.ambient)
            }
            MenuItem {
                text: qsTr("Calibrate")
                color: FiatLuxTheme.primaryText
                onClicked: pageStack.push(Qt.resolvedUrl("CalibratePage.qml"))
            }
            MenuItem {
                visible: rollId >= 0
                text: qsTr("Close roll")
                color: FiatLuxTheme.primaryText
                onClicked: {
                    Storage.closeRoll(rollId)
                    app.reloadRolls()
                    loadQuick()
                }
            }
            MenuItem {
                text: qsTr("New roll")
                color: FiatLuxTheme.primaryText
                onClicked: pageStack.push(Qt.resolvedUrl("AddRollPage.qml"), { returnToMeter: true })
            }
            MenuItem {
                text: qsTr("Film stocks")
                color: FiatLuxTheme.primaryText
                onClicked: pageStack.push(Qt.resolvedUrl("FilmPage.qml"))
            }
            MenuItem {
                text: qsTr("Lenses")
                color: FiatLuxTheme.primaryText
                onClicked: pageStack.push(Qt.resolvedUrl("LensesPage.qml"))
            }
            MenuItem {
                text: qsTr("Cameras")
                color: FiatLuxTheme.primaryText
                onClicked: pageStack.push(Qt.resolvedUrl("CamerasPage.qml"))
            }
        }

        Column {
            id: contentColumn
            width: page.width
            spacing: Theme.paddingMedium

            // ---- top bar ----
            //
            // The wordmark and the source pill both sit ON the system
            // indicator row rather than below it. They are short and they live
            // in the corners, so the centred cutout never reaches either.
            Item {
                width: parent.width
                height: FiatLuxTheme.statusRowCenter + sourcePill.height / 2 + Theme.paddingMedium

                Text {
                    id: wordmark
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.horizontalPageMargin
                    anchors.top: parent.top
                    anchors.topMargin: Math.max(0, FiatLuxTheme.statusRowCenter - height / 2)
                    text: "fiat lux"
                    color: FiatLuxTheme.primaryText
                    font.pixelSize: Theme.fontSizeLarge
                    font.family: FiatLuxTheme.serif
                    font.italic: true
                }

                BackgroundItem {
                    id: sourcePill
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.horizontalPageMargin
                    anchors.top: parent.top
                    anchors.topMargin: Math.max(0, FiatLuxTheme.statusRowCenter - height / 2)
                    width: pillRow.width + Theme.paddingLarge * 2
                    height: Theme.itemSizeSmall
                    highlightedColor: FiatLuxTheme.highlightWash
                    onClicked: {
                        var arr = ["Quick Meter"]
                        for (var i = 0; i < app.cameraModel.count; i++)
                            arr.push(app.cameraModel.get(i).name)
                        sourceMenu.items = arr
                        sourceMenu.show(sourcePill)
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: sourcePill.highlighted ? FiatLuxTheme.pillFillActive : FiatLuxTheme.pillFill
                        border.color: FiatLuxTheme.pillBorderActive
                        border.width: 1
                    }
                    Row {
                        id: pillRow
                        anchors.centerIn: parent
                        spacing: Theme.paddingSmall
                        Text {
                            text: rollId >= 0 ? sourceLabel + " · " + shotCount + "fr" : sourceLabel
                            color: FiatLuxTheme.primaryText
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: FiatLuxTheme.serif
                            font.italic: true
                        }
                        Text {
                            text: "▾"
                            color: FiatLuxTheme.accent
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                }
            }

            // ---- viewfinder ----
            //
            // The one fixed dark surface in the app, and the one place a fixed
            // colour is right: it stands in for a camera feed. Everything
            // drawn on it is fixed too, for the same reason -- and because
            // this whole rectangle is what gets saved when you log a shot.
            Rectangle {
                id: viewfinder
                width: page.width
                height: page.width
                color: FiatLuxTheme.viewfinderBg
                clip: true

                VideoOutput {
                    id: vo
                    source: page.cam
                    anchors.centerIn: parent
                    // Manual "crop to fill": overfill the square, parent clips.
                    property real ar: sourceRect.height > 0
                                      ? sourceRect.width / sourceRect.height : 1
                    width:  ar >= 1 ? parent.height * ar : parent.width
                    height: ar >= 1 ? parent.height : parent.width / ar
                    fillMode: VideoOutput.PreserveAspectFit
                    orientation: page.viewfinderOrientation
                    visible: page.cameraLive
                }

                // Live: refocus. Black: build a new camera. Tapping the picture
                // is what anyone tries first in either situation, so it is
                // worth making that the thing that works.
                MouseArea {
                    anchors.fill: parent
                    onClicked: page.cameraLive ? page.refocus() : page.reloadCamera()
                }

                Column {
                    anchors.centerIn: parent
                    width: parent.width - Theme.horizontalPageMargin * 2
                    spacing: Theme.paddingSmall
                    visible: !page.cameraLive

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: qsTr("tap to wake the camera")
                        color: FiatLuxTheme.viewfinderText
                        opacity: 0.7
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: FiatLuxTheme.serif
                        font.italic: true
                    }

                    // The truth, in small type.
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: page.cameraNote !== "" ? page.cameraNote : page.cameraStatusName()
                        color: FiatLuxTheme.viewfinderText
                        opacity: 0.4
                        font.pixelSize: Theme.fontSizeExtraSmall
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: hudRow.height + Theme.paddingMedium * 2
                    color: Qt.rgba(0, 0, 0, 0.65)
                    Row {
                        id: hudRow
                        anchors.centerIn: parent
                        spacing: Theme.paddingLarge
                        Text {
                            // Comma operator: read the dependencies, show the last value.
                            text: (page.apertures,
                                   exposureList.currentIndex,
                                   "f/" + currentAperture())
                            color: FiatLuxTheme.viewfinderText
                            font.pixelSize: Theme.fontSizeMedium
                        }
                        Text {
                            text: (page.iso, page.ev, page.shutterSpeeds,
                                   exposureList.currentIndex, currentSpeed())
                            color: FiatLuxTheme.viewfinderAccent
                            font.pixelSize: Theme.fontSizeMedium
                        }
                        Text {
                            text: "ISO " + iso
                            color: FiatLuxTheme.viewfinderText
                            font.pixelSize: Theme.fontSizeMedium
                        }
                    }
                }

                Rectangle {
                    id: shotFlash
                    anchors.fill: parent
                    color: FiatLuxTheme.viewfinderText
                    opacity: 0
                    function restart() { flashAnim.restart() }
                    NumberAnimation {
                        id: flashAnim
                        target: shotFlash
                        property: "opacity"
                        from: 0.6; to: 0.0; duration: 350
                    }
                }
            }

            // ---- exposure scroller ----
            Rectangle {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                height: Theme.itemSizeLarge * 2
                radius: FiatLuxTheme.cardRadius
                color: FiatLuxTheme.card
                border.color: evLocked ? FiatLuxTheme.accent : FiatLuxTheme.cardBorder
                border.width: evLocked ? FiatLuxTheme.cardBorderWidth : 1
                clip: true

                ListView {
                    id: exposureList
                    anchors.fill: parent
                    orientation: ListView.Horizontal
                    snapMode: ListView.SnapToItem
                    highlightRangeMode: ListView.StrictlyEnforceRange
                    preferredHighlightBegin: width / 2 - Theme.itemSizeHuge / 2
                    preferredHighlightEnd:   width / 2 + Theme.itemSizeHuge / 2
                    clip: true
                    // scrollerGen in the expression forces full delegate rebuild on camera switch
                    model: (scrollerGen, apertures.length)

                    // Whatever you land on is what the cover should show.
                    onCurrentIndexChanged: page.publishReading()

                    delegate: Item {
                        width: Theme.itemSizeHuge
                        height: exposureList.height
                        property bool isCenter: ListView.isCurrentItem
                        // Touch every dependency directly — QML only tracks
                        // properties read in the binding, not inside calls.
                        property int shutterIdx: {
                            var _g = page.scrollerGen
                            var _i = page.iso
                            var _e = page.ev
                            var _a = page.apertures
                            var _s = page.shutterSpeeds
                            return calcShutterIndex(index)
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width - Theme.paddingSmall * 2
                            height: parent.height - Theme.paddingLarge * 2
                            radius: Theme.paddingLarge
                            color: FiatLuxTheme.pillFillActive
                            border.color: FiatLuxTheme.accent
                            border.width: 1
                            visible: isCenter
                        }
                        Column {
                            anchors.centerIn: parent
                            spacing: Theme.paddingSmall
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: (shutterSpeeds && shutterSpeeds.length > shutterIdx)
                                      ? shutterSpeeds[shutterIdx] : "-"
                                color: isCenter ? FiatLuxTheme.accent : FiatLuxTheme.secondaryText
                                font.pixelSize: isCenter ? Theme.fontSizeLarge : Theme.fontSizeMedium
                                font.bold: isCenter
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: (apertures && apertures.length > index)
                                      ? "f/" + apertures[index] : "-"
                                color: isCenter ? FiatLuxTheme.primaryText : FiatLuxTheme.secondaryText
                                font.pixelSize: isCenter ? Theme.fontSizeLarge : Theme.fontSizeMedium
                                font.bold: isCenter
                            }
                        }
                    }
                }
            }

            // ---- ISO + lens row ----
            Row {
                x: Theme.horizontalPageMargin
                spacing: Theme.paddingMedium

                BackgroundItem {
                    id: isoBtn
                    visible: !editingIso
                    width: isoPillBg.width
                    height: isoPillBg.height
                    highlightedColor: FiatLuxTheme.highlightWash
                    onClicked: isoMenu.show(isoBtn)
                    Rectangle {
                        id: isoPillBg
                        radius: height / 2
                        color: isoBtn.highlighted ? FiatLuxTheme.pillFillActive : FiatLuxTheme.pillFill
                        border.color: FiatLuxTheme.pillBorder
                        border.width: 1
                        width: isoLbl.width + Theme.paddingLarge * 2
                        height: isoLbl.height + Theme.paddingMedium
                        Text {
                            id: isoLbl
                            anchors.centerIn: parent
                            text: "ISO " + iso
                            color: FiatLuxTheme.primaryText
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                }

                Row {
                    visible: editingIso
                    spacing: Theme.paddingSmall
                    TextField {
                        id: isoEditor
                        width: Theme.itemSizeMedium
                        text: iso.toString()
                        color: FiatLuxTheme.primaryText
                        inputMethodHints: Qt.ImhDigitsOnly
                        maximumLength: 5
                        validator: IntValidator { bottom: 1; top: 99999 }
                        onTextChanged: { var n = parseInt(text); if (!isNaN(n) && n > 0) iso = n }
                        EnterKey.onClicked: { editingIso = false; page.publishReading() }
                    }
                    IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        icon.source: "image://theme/icon-m-accept"
                        onClicked: { editingIso = false; page.publishReading() }
                    }
                }

                BackgroundItem {
                    id: lensBtn
                    visible: lens.length > 0
                    width: lensPillBg.width
                    height: lensPillBg.height
                    highlightedColor: FiatLuxTheme.highlightWash
                    onClicked: {
                        if (compatLenses.length <= 1) return
                        var arr = []
                        for (var i = 0; i < compatLenses.length; i++) arr.push(compatLenses[i].name)
                        lensMenu.items = arr
                        lensMenu.show(lensBtn)
                    }
                    Rectangle {
                        id: lensPillBg
                        radius: height / 2
                        color: lensBtn.highlighted ? FiatLuxTheme.pillFillActive : FiatLuxTheme.pillFill
                        border.color: FiatLuxTheme.pillBorder
                        border.width: 1
                        width: Math.min(lensLbl.implicitWidth + Theme.paddingLarge * 2,
                                        page.width - 2 * Theme.horizontalPageMargin - 160)
                        height: lensLbl.height + Theme.paddingMedium
                        Text {
                            id: lensLbl
                            anchors.centerIn: parent
                            width: parent.width - Theme.paddingLarge * 2
                            text: lens
                            color: FiatLuxTheme.primaryText
                            font.pixelSize: Theme.fontSizeSmall
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            // ---- what this meter is ----
            //
            // Said here, at the moment of use, and not in an about page. An
            // incident meter used like a reflected one gives a confident wrong
            // answer, which is the worst kind, and the only defence is to name
            // the method where the person is actually looking.
            //
            // The reflected pills are gone. Not hidden -- gone. This phone's
            // camera reports t 0 and S 0, so there was never a second method
            // to choose between; the pill offered a choice the hardware could
            // not honour.
            Column {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                spacing: 0

                Label {
                    width: parent.width
                    text: qsTr("incident · point the screen at the camera")
                    font.pixelSize: Theme.fontSizeExtraSmall
                    font.bold: true
                    color: FiatLuxTheme.accent
                }

                Label {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: qsTr("Measured from the subject, not from the camera. Calibrated for daylight — under a lamp it reads bright.")
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: FiatLuxTheme.secondaryText
                }
            }

            // ---- measure button ----
            BackgroundItem {
                id: measureBtn
                width: parent.width
                height: Theme.itemSizeLarge
                onClicked: page.measure()
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    height: Theme.itemSizeMedium
                    radius: Theme.paddingLarge
                    color: measureBtn.highlighted
                           ? Qt.darker(FiatLuxTheme.accent, 1.2) : FiatLuxTheme.accent
                    Row {
                        anchors.centerIn: parent
                        spacing: Theme.paddingMedium
                        Text {
                            text: evLocked ? qsTr("remeasure") : qsTr("measure")
                            color: FiatLuxTheme.markOn(FiatLuxTheme.accent)
                            font.pixelSize: Theme.fontSizeMedium
                            font.family: FiatLuxTheme.serif
                            font.italic: true
                            font.bold: true
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            visible: evLocked
                            text: "EV " + ev.toFixed(1)
                            color: FiatLuxTheme.markOn(FiatLuxTheme.accent)
                            font.pixelSize: Theme.fontSizeSmall
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }

            // What the last action actually did. Visible on purpose: a meter
            // that silently substitutes one method for another is worse than
            // one that admits it, and a log that silently drops the picture is
            // worse than one that says the picture is missing.
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: page.meterNote !== ""
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                text: page.meterNote
                font.pixelSize: Theme.fontSizeExtraSmall
                color: FiatLuxTheme.secondaryText
            }

            // ---- log shot ----
            //
            // One button, one job. It was two -- "log shot" and "capture" --
            // which asked you to decide whether this frame deserved a picture.
            // It always does: the picture IS the log entry, with the reading
            // already burnt into it.
            //
            // No icon. image://theme/ icons are drawn in the ambience's
            // primary colour, which under Fiat colours on a dark ambience is
            // white on a white button. The word does the job on its own.
            BackgroundItem {
                id: captureBtn
                width: parent.width
                height: Theme.itemSizeLarge
                enabled: page.cameraLive
                opacity: enabled ? 1.0 : 0.4
                onClicked: page.logShotWithFrame()
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    height: Theme.itemSizeMedium
                    radius: Theme.paddingLarge
                    color: captureBtn.highlighted ? FiatLuxTheme.pillFillActive : FiatLuxTheme.card
                    border.color: FiatLuxTheme.accent
                    border.width: 1
                    Text {
                        anchors.centerIn: parent
                        text: qsTr("log shot")
                        color: FiatLuxTheme.primaryText
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: FiatLuxTheme.serif
                        font.italic: true
                    }
                }
            }

            Item { width: 1; height: Theme.paddingLarge }
        }
    }

    PillMenu {
        id: sourceMenu
        onPicked: function(idx) {
            page.evLocked = false
            page.meterNote = ""
            if (idx === 0) page.loadQuick()
            else page.loadCamera(app.cameraModel.get(idx - 1).id)
        }
    }

    PillMenu {
        id: isoMenu
        items: [25,50,64,100,125,160,200,250,320,400,500,640,800,1000,1250,1600,2500,3200,6400,"Custom…"]
        onPicked: function(idx) {
            if (typeof items[idx] === "string") page.editingIso = true
            else { page.iso = items[idx]; page.publishReading() }
        }
    }

    PillMenu {
        id: lensMenu
        onPicked: function(idx) {
            page.lensIndex = idx
            page.applyLens()
        }
    }
}
