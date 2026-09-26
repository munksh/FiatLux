import QtQuick 2.0
import Sailfish.Silica 1.0
import se.munkstolen.fiatlux 1.0
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
    property real ev: 8.0
    property bool evLocked: false
    property bool editingIso: false
    property int shotCount: 0

    // The camera being metered for (-1 = Quick Meter) and the film in it.
    // Only Quick Meter lets you pick an ISO; a camera meters its film's.
    property int cameraId: -1
    property string filmLabel: ""
    property string cameraApertures: ""
    readonly property bool quickMeter: page.cameraId < 0

    // Raise when the introduction changes enough to be worth showing again.
    readonly property int introVersion: 1
    property bool introChecked: false
    ConfigurationValue { id: cfgIntro; key: "/apps/harbour-fiatlux/introVersion"; defaultValue: 0 }
    Timer {
        id: introTimer
        interval: 400
        onTriggered: {
            if (cfgIntro.value < page.introVersion)
                pageStack.push(Qt.resolvedUrl("IntroPage.qml"), { version: page.introVersion })
        }
    }
    onStatusChanged: {
        if (status === PageStatus.Active && !page.introChecked) {
            page.introChecked = true
            introTimer.start()
        }
    }

    // Fallback only. picturesPath() asks the platform first.
    property string picturesDir: "/home/defaultuser/Pictures"

    // Rotation of the Camera2 frames on screen. Try 0 / 90 / 180 / 270.
    property int viewfinderOrientation: 90

    property string meterNote: ""

    // Where the scroller lands after a measurement \u2014 handheld default 1/125 s.
    property real preferredSpeed: 1/125

    readonly property var defaultApertures: ["1","1.4","1.7","2","2.8","4","5.6","8","11","16","22"]
    readonly property var defaultSpeeds: ["1/1000","1/500","1/250","1/125","1/60","1/30","1/15","1/8","1/4","1/2","1\""]

    // ---- calibration -----------------------------------------------------
    //
    // In stops, in dconf, so the calibrate page and the meter read the same
    // number. A new key: the old evCalibration belonged to the light sensor
    // and means nothing for the camera. The guard matters -- a dconf value
    // reads back undefined before the key exists, and undefined arithmetic
    // gives NaN, which would make every reading vanish.
    ConfigurationValue {
        id: cfgCalibration
        key: "/apps/harbour-fiatlux/evCalibrationReflected"
        defaultValue: 4.0
    }
    readonly property real evCalibration: {
        var v = cfgCalibration.value
        if (v === undefined || v === null) return 4.0
        return v
    }

    // ---- what the cover reads --------------------------------------------

    ConfigurationValue { id: cfgAperture; key: "/apps/harbour-fiatlux/lastAperture"; defaultValue: "" }
    ConfigurationValue { id: cfgSpeed;    key: "/apps/harbour-fiatlux/lastSpeed";    defaultValue: "" }
    ConfigurationValue { id: cfgCamera;   key: "/apps/harbour-fiatlux/lastCamera";   defaultValue: "" }
    ConfigurationValue { id: cfgIso;      key: "/apps/harbour-fiatlux/lastIso";      defaultValue: 0 }
    ConfigurationValue { id: cfgFilm;     key: "/apps/harbour-fiatlux/lastFilm";     defaultValue: "" }

    function publishReading() {
        // Nothing has been metered, so there is nothing to show. Publishing
        // the default 8.0 would put a number on the cover that no one chose.
        if (!page.evLocked) return
        var a = page.apertures
        var s = page.shutterSpeeds
        var i = exposureList.currentIndex
        if (!a || !s || i < 0 || i >= a.length) return
        var k = page.speedIndexFor(parseFloat(a[i]), page.ev, page.iso, s)
        if (k < 0 || k >= s.length) return
        cfgAperture.value = a[i]
        cfgSpeed.value = s[k]
        cfgCamera.value = page.sourceLabel
        cfgIso.value = page.iso
        cfgFilm.value = page.rollId >= 0 ? page.filmLabel : ""
    }

    // ---- the current pair, as bindings rather than function calls ---------
    //
    // These used to be functions called from bindings with the dependencies
    // smuggled in through a comma expression. That works, but it is a trick,
    // the linter flags it as M30, and the next person to tidy it up breaks
    // every readout in the app without a single error message.

    readonly property string currentApertureText: {
        var a = page.apertures
        var idx = exposureList.currentIndex
        if (!a || a.length === 0) return "-"
        if (idx < 0 || idx >= a.length) return "-"
        return a[idx]
    }

    readonly property int currentShutterIndex: {
        var a = page.apertures
        var idx = exposureList.currentIndex
        if (!a || a.length === 0) return 0
        if (idx < 0 || idx >= a.length) return 0
        return page.speedIndexFor(parseFloat(a[idx]), page.ev, page.iso, page.shutterSpeeds)
    }

    readonly property string currentSpeedText: {
        var s = page.shutterSpeeds
        var k = page.currentShutterIndex
        if (!s || s.length === 0) return "-"
        if (k < 0 || k >= s.length) return "-"
        return s[k]
    }

    // ---- loading a source -------------------------------------------------

    Component.onCompleted: {
        if (page.rollId >= 0) page.loadRoll(page.rollId)
        else if (page.presetCameraId >= 0) page.loadCamera(page.presetCameraId)
        else page.loadQuick()
    }

    function loadQuick() {
        rollId = -1
        cameraId = -1
        sourceLabel = "Quick Meter"
        filmLabel = ""
        cameraType = 0
        mount = ""
        bodySpeeds = ""
        cameraApertures = ""
        iso = 400
        isoLocked = false
        compatLenses = []
        lensIndex = 0
        shotCount = 0
        applyLens()
    }

    // A camera with film in it meters that film. An empty one keeps the last
    // ISO and asks for film.
    function loadCamera(id) {
        var open = Storage.openRollForCamera(id)
        if (open >= 0) { loadRoll(open); return }
        var c = Storage.getCamera(id)
        if (!c) { loadQuick(); return }
        rollId = -1
        cameraId = c.id
        sourceLabel = c.name
        filmLabel = ""
        cameraType = c.type
        mount = c.mount || ""
        bodySpeeds = c.bodySpeeds || ""
        cameraApertures = c.apertures || ""
        isoLocked = true
        compatLenses = cameraType !== 0 && mount.length > 0 ? Storage.lensesForMount(mount) : []
        lensIndex = 0
        shotCount = 0
        applyLens()
    }

    function loadRoll(id) {
        var r = Storage.getRoll(id)
        if (!r) { loadQuick(); return }
        rollId = id
        cameraId = r.cameraId ? r.cameraId : -1
        sourceLabel = r.cameraName !== "" ? r.cameraName : "Quick Meter"
        filmLabel = r.stockName
        cameraType = r.cameraType ? r.cameraType : 0
        mount = r.mount || ""
        bodySpeeds = r.bodySpeeds || ""
        cameraApertures = r.cameraApertures || ""
        iso = r.pushIso
        isoLocked = true
        compatLenses = cameraType !== 0 && mount.length > 0 ? Storage.lensesForMount(mount) : []
        lensIndex = 0
        for (var i = 0; i < compatLenses.length; i++) {
            if (compatLenses[i].id === r.lensId) {
                lensIndex = i
                break
            }
        }
        applyLens()
        shotCount = Storage.shotCountForRoll(id)
    }

    // Where the apertures and speeds come from:
    //   fixed lens      both from the camera
    //   otherwise       apertures from the lens; speeds from the lens, else
    //                   the body, else the defaults (the data is incomplete)
    // split() always returns a fresh array, and a new array identity is what
    // makes the ListView rebuild.
    function applyLens() {
        var bSpeeds = (bodySpeeds && bodySpeeds.length > 0) ? bodySpeeds : ""
        if (cameraType === 0 && cameraApertures.length > 0) {
            lens = ""
            apertures = cameraApertures.split(",")
            shutterSpeeds = bSpeeds.length > 0 ? bSpeeds.split(",") : defaultSpeeds.slice()
        } else if (compatLenses.length > 0) {
            var l = compatLenses[lensIndex]
            lens = l.name
            apertures = (l.apertures || "").split(",")
            var lSpeeds = (l.speeds && l.speeds.length > 0) ? l.speeds : ""
            if (lSpeeds.length > 0) shutterSpeeds = lSpeeds.split(",")
            else if (bSpeeds.length > 0) shutterSpeeds = bSpeeds.split(",")
            else shutterSpeeds = defaultSpeeds.slice()
        } else {
            lens = ""
            apertures = defaultApertures.slice()
            shutterSpeeds = bSpeeds.length > 0 ? bSpeeds.split(",") : defaultSpeeds.slice()
        }
    }

    // ---- the exposure arithmetic -----------------------------------------
    //
    // Every input is an argument. Nothing here reads a page property, so a
    // binding that calls one of these has already read everything it depends
    // on in order to make the call, and QML tracks it with no tricks.

    function parseSpeed(s) {
        if (s === "B") return null
        if (s.indexOf("/") !== -1) {
            var p = s.split("/")
            return parseFloat(p[0]) / parseFloat(p[1])
        }
        return parseFloat(s.replace("\"", ""))
    }

    // The exact time this aperture needs, in seconds. t = N^2 / (2^EV * S/100)
    function exactSpeedFor(apertureValue, evValue, isoValue) {
        if (!(apertureValue > 0)) return NaN
        return (apertureValue * apertureValue) / (Math.pow(2, evValue) * (isoValue / 100))
    }

    // Which of the camera's OWN speeds sits closest. Compared in stops, not in
    // raw seconds -- otherwise long speeds always look further away than short
    // ones and the meter drifts towards 1/1000 on every scene.
    function speedIndexFor(apertureValue, evValue, isoValue, speeds) {
        if (!speeds || speeds.length === 0) return 0
        var wanted = exactSpeedFor(apertureValue, evValue, isoValue)
        if (isNaN(wanted)) return 0
        var closest = 0
        var diff = Infinity
        for (var i = 0; i < speeds.length; i++) {
            var sv = parseSpeed(speeds[i])
            if (sv === null || sv <= 0) continue
            var d = Math.abs(Math.log(sv / wanted) / Math.LN2)
            if (d < diff) {
                diff = d
                closest = i
            }
        }
        return closest
    }

    function suggestIndex() {
        var a = page.apertures
        var s = page.shutterSpeeds
        if (!a || a.length === 0 || !s || s.length === 0) return 0
        var best = 0
        var diff = Infinity
        for (var i = 0; i < a.length; i++) {
            var k = page.speedIndexFor(parseFloat(a[i]), page.ev, page.iso, s)
            var sv = page.parseSpeed(s[k])
            if (sv === null || sv <= 0) continue
            var d = Math.abs(Math.log(sv / page.preferredSpeed) / Math.LN2)
            if (d < diff) {
                diff = d
                best = i
            }
        }
        return best
    }

    // ---- measuring --------------------------------------------------------
    //
    // Reflected, through the lens: the ISO and exposure time the camera's
    // auto-exposure chose for the current frame, and the lens's fixed aperture.
    //
    //   EV100 = log2(N^2 / t) - log2(S / 100)
    //
    // Like any reflected meter it takes what it sees for mid-grey, so snow
    // reads dark and a black cat reads bright. Tap the viewfinder to meter a
    // spot rather than the whole frame.

    function formatSeconds(t) {
        if (!(t > 0)) return "-"
        if (t < 1) return "1/" + Math.round(1 / t)
        return t.toFixed(1) + "\""
    }

    function measure() {
        if (!meter.metered) {
            page.meterNote = meter.errorString !== ""
                    ? meter.errorString
                    : qsTr("no reading from the camera yet")
            return
        }
        page.meterNote = ""
        page.ev = meter.ev100 + page.evCalibration
        page.evLocked = true
        exposureList.currentIndex = page.suggestIndex()
        page.publishReading()
    }

    // ---- logging a shot ---------------------------------------------------
    //
    // The frame is grabbed from the VIEWFINDER ITEM, not from the camera's
    // still capture -- which means the HUD comes with it. The aperture, the
    // speed and the film speed are already drawn over the picture, so they are
    // burnt in for free and they are exactly what you were looking at when you
    // pressed.
    //
    // It is screen resolution and not the sensor's, and that is the right
    // trade. This is a note about what you metered. The photograph is on film.

    function picturesPath() {
        try {
            if (typeof StandardPaths !== "undefined" && StandardPaths.pictures) {
                var p = "" + StandardPaths.pictures
                if (p.indexOf("file://") === 0) return p.substring(7)
                return p
            }
        } catch (e) { }
        return page.picturesDir
    }

    function logShot(photoPath) {
        if (page.rollId < 0) return
        Storage.addShot(page.rollId, new Date().toISOString(), page.ev,
                        page.currentApertureText, page.currentSpeedText,
                        page.iso, photoPath || "")
        page.shotCount = Storage.shotCountForRoll(page.rollId)
    }

    function logShotWithFrame() {
        var name = "fiatlux-" + new Date().toISOString().replace(/[:.]/g, "-") + ".png"
        var path = page.picturesPath() + "/" + name

        var started = viewfinder.grabToImage(function(result) {
            // The flash fires AFTER the grab, never before. grabToImage renders
            // the next frame of this item, and the flash is a cream rectangle
            // at 0.6 opacity across the whole viewfinder -- start it first and
            // it is in the picture. That was why saved frames came out bright.
            shotFlash.restart()

            if (result.saveToFile(path)) {
                page.logShot(path)
                if (page.rollId >= 0) page.meterNote = qsTr("logged � %1").arg(name)
                else page.meterNote = qsTr("saved %1 \u2014 open a roll to log it").arg(name)
            } else {
                page.logShot("")
                page.meterNote = qsTr("could not write to Pictures \u2014 logged without the frame")
            }
        })

        if (!started) {
            shotFlash.restart()
            page.logShot("")
            page.meterNote = qsTr("could not grab the frame \u2014 logged without it")
        }
    }

    // ---- is the app actually in front of you? -----------------------------
    //
    // POLLED, not bound. Qt.application.state is correct when you read it, but
    // on Sailfish its change signal does not reliably arrive -- a QML binding
    // on it evaluates once, latches to whatever was true at load, and never
    // updates again. That is one of the two faults that made the camera look
    // unrecoverable; reading the value once a second cannot latch.

    property int appState: Qt.ApplicationActive
    property int pageState: PageStatus.Active
    property string diag: ""

    Timer {
        id: statePoll
        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            page.appState = Qt.application.state
            page.pageState = page.status
            page.diag = page.cameraStatusName()
                      + " � app " + page.appStateName()
                      + " � page " + page.pageStatusName()
        }
    }

    readonly property bool cameraWanted:
        page.pageState === PageStatus.Active && page.appState === Qt.ApplicationActive

    readonly property bool cameraLive: meter.running && meter.hasFrame

    property string cameraNote: ""

    // ---- the camera -------------------------------------------------------
    //
    // Camera2, through RAWfish's helper, /usr/libexec/rawfish/sfos-camera2-probe.
    // It streams the preview frames and, whenever auto-exposure changes its
    // mind, the ISO and exposure time it chose. Camera2Meter, in the
    // viewfinder below, is both the picture and the meter. Only one process
    // can hold the camera, so it stops whenever this page is not in front.

    function reloadCamera() {
        page.cameraNote = ""
        meter.restart()
    }

    // Only for the placeholder: a viewfinder that names its state is a bug
    // report you can read without a laptop.
    function cameraStatusName() {
        if (!meter.available) return "no Camera2 helper"
        if (!meter.running) return "stopped"
        if (!meter.hasFrame) return "starting"
        return "live"
    }

    function appStateName() {
        switch (page.appState) {
        case Qt.ApplicationSuspended: return "suspended"
        case Qt.ApplicationHidden:    return "hidden"
        case Qt.ApplicationInactive:  return "inactive"
        case Qt.ApplicationActive:    return "active"
        default:                      return "?" + page.appState
        }
    }

    function pageStatusName() {
        switch (page.pageState) {
        case PageStatus.Inactive:     return "inactive"
        case PageStatus.Activating:   return "activating"
        case PageStatus.Active:       return "active"
        case PageStatus.Deactivating: return "deactivating"
        default:                      return "?" + page.pageState
        }
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
                text: qsTr("About")
                color: FiatLuxTheme.primaryText
                onClicked: pageStack.push(Qt.resolvedUrl("AboutPage.qml"))
            }
            MenuItem {
                text: FiatLuxTheme.ambient ? qsTr("Fiat colours") : qsTr("Follow ambience")
                color: FiatLuxTheme.primaryText
                onClicked: FiatLuxTheme.setAmbient(!FiatLuxTheme.ambient)
            }
            MenuItem {
                text: qsTr("Calibrate")
                color: FiatLuxTheme.primaryText
                onClicked: pageStack.push(Qt.resolvedUrl("CalibratePage.qml"))
            }
            MenuItem {
                visible: page.rollId >= 0
                text: qsTr("Unload film")
                color: FiatLuxTheme.primaryText
                onClicked: {
                    var cam = page.cameraId
                    Storage.closeRoll(page.rollId)
                    app.reloadRolls()
                    if (cam >= 0) page.loadCamera(cam)
                    else page.loadQuick()
                }
            }
            MenuItem {
                text: qsTr("Load film")
                color: FiatLuxTheme.primaryText
                onClicked: pageStack.push(Qt.resolvedUrl("AddRollPage.qml"), { presetCameraId: page.cameraId })
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
            // The wordmark and the source pill both sit ON the system indicator
            // row rather than below it. They are short and they live in the
            // corners, so the centred cutout never reaches either.
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
                        for (var i = 0; i < app.cameraModel.count; i++) {
                            var c = app.cameraModel.get(i)
                            var r = Storage.openRollForCamera(c.id)
                            var film = r >= 0 ? Storage.getRoll(r) : null
                            arr.push(film ? c.name + " \u00b7 " + film.stockName : c.name)
                        }
                        sourceMenu.items = arr
                        sourceMenu.show(sourcePill)
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: sourcePill.highlighted ? FiatLuxTheme.pillFillActive
                                                      : FiatLuxTheme.pillFill
                        border.color: FiatLuxTheme.pillBorderActive
                        border.width: 1
                    }
                    Row {
                        id: pillRow
                        anchors.centerIn: parent
                        spacing: Theme.paddingSmall
                        Text {
                            text: page.sourceLabel
                            color: FiatLuxTheme.primaryText
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: FiatLuxTheme.serif
                            font.italic: true
                        }
                        Text {
                            text: "\u25be"
                            color: FiatLuxTheme.accent
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                }
            }

            // ---- viewfinder ----
            //
            // The one fixed dark surface in the app, and the one place a fixed
            // colour is right: it stands in for a camera feed. Everything drawn
            // on it is fixed too, for the same reason -- and because this whole
            // rectangle is what gets saved when you log a shot.
            Rectangle {
                id: viewfinder
                width: page.width
                height: page.width
                color: FiatLuxTheme.viewfinderBg
                clip: true

                Camera2Meter {
                    id: meter
                    anchors.fill: parent
                    fill: true
                    orientation: page.viewfinderOrientation
                    active: page.status === PageStatus.Active
                            && page.appState === Qt.ApplicationActive
                    onErrorStringChanged: page.cameraNote = errorString
                }

                Rectangle {
                    id: spotMark
                    visible: meter.spot && page.cameraLive
                    width: Theme.itemSizeSmall
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.color: FiatLuxTheme.viewfinderText
                    border.width: 2
                    opacity: 0.8
                }

                // Tap: meter that spot. Press and hold: the whole frame again.
                // While the camera is down, a tap starts it.
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (!page.cameraLive) {
                            page.reloadCamera()
                            return
                        }
                        spotMark.x = mouse.x - spotMark.width / 2
                        spotMark.y = mouse.y - spotMark.height / 2
                        meter.meterAt(mouse.x / width, mouse.y / height)
                    }
                    onPressAndHold: meter.meterWholeFrame()
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

                    // page.diag is refreshed by statePoll, so this line actually
                    // updates. A function call in a binding would not, because
                    // QML has no way to know when its answer changed.
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: page.cameraNote !== "" ? page.cameraNote : page.diag
                        color: FiatLuxTheme.viewfinderText
                        opacity: 0.4
                        font.pixelSize: Theme.fontSizeExtraSmall
                    }
                }

                // The strip that is burnt into every logged frame: the pair,
                // the film speed, and which camera, film and frame it was.
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: hudCol.height + Theme.paddingMedium * 2
                    color: Qt.rgba(0, 0, 0, 0.65)
                    Column {
                        id: hudCol
                        anchors.centerIn: parent
                        width: parent.width - Theme.horizontalPageMargin * 2
                        spacing: Theme.paddingSmall
                        Row {
                            id: hudRow
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: Theme.paddingLarge
                            Text {
                                text: "f/" + page.currentApertureText
                                color: FiatLuxTheme.viewfinderText
                                font.pixelSize: Theme.fontSizeMedium
                            }
                            Text {
                                text: page.currentSpeedText
                                color: FiatLuxTheme.viewfinderAccent
                                font.pixelSize: Theme.fontSizeMedium
                            }
                            Text {
                                text: "ISO " + page.iso
                                color: FiatLuxTheme.viewfinderText
                                font.pixelSize: Theme.fontSizeMedium
                            }
                        }
                        Text {
                            visible: !page.quickMeter
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideMiddle
                            text: page.rollId >= 0
                                  ? page.sourceLabel + "  \u00b7  " + page.filmLabel
                                    + "  \u00b7  " + qsTr("frame %1").arg(page.shotCount + 1)
                                  : page.sourceLabel + "  \u00b7  " + qsTr("no film")
                            color: FiatLuxTheme.viewfinderText
                            opacity: 0.8
                            font.pixelSize: Theme.fontSizeExtraSmall
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
                        from: 0.6
                        to: 0.0
                        duration: 350
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
                border.color: page.evLocked ? FiatLuxTheme.accent : FiatLuxTheme.cardBorder
                border.width: page.evLocked ? FiatLuxTheme.cardBorderWidth : 1
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

                    // The array itself is the model. applyLens() always hands
                    // over a NEW array -- split() and slice() both do -- so the
                    // identity changes and the view rebuilds. The old code kept
                    // a scrollerGen counter to force that; the counter was
                    // solving a problem slice() had already solved.
                    model: page.apertures

                    onCurrentIndexChanged: page.publishReading()

                    delegate: Item {
                        id: card
                        width: Theme.itemSizeHuge
                        height: exposureList.height

                        readonly property bool isCenter: ListView.isCurrentItem
                        readonly property real apertureValue: parseFloat(modelData)

                        readonly property int shutterIdx:
                            page.speedIndexFor(card.apertureValue, page.ev,
                                               page.iso, page.shutterSpeeds)

                        readonly property string speedText: {
                            var s = page.shutterSpeeds
                            var k = card.shutterIdx
                            if (!s || s.length === 0) return "-"
                            if (k < 0 || k >= s.length) return "-"
                            return s[k]
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width - Theme.paddingSmall * 2
                            height: parent.height - Theme.paddingLarge * 2
                            radius: Theme.paddingLarge
                            color: FiatLuxTheme.pillFillActive
                            border.color: FiatLuxTheme.accent
                            border.width: 1
                            visible: card.isCenter
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: Theme.paddingSmall
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: card.speedText
                                color: card.isCenter ? FiatLuxTheme.accent
                                                     : FiatLuxTheme.secondaryText
                                font.pixelSize: card.isCenter ? Theme.fontSizeLarge
                                                              : Theme.fontSizeMedium
                                font.bold: card.isCenter
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "f/" + modelData
                                color: card.isCenter ? FiatLuxTheme.primaryText
                                                     : FiatLuxTheme.secondaryText
                                font.pixelSize: card.isCenter ? Theme.fontSizeLarge
                                                              : Theme.fontSizeMedium
                                font.bold: card.isCenter
                            }
                        }
                    }
                }
            }

            // ---- ISO and lens ----
            Row {
                x: Theme.horizontalPageMargin
                spacing: Theme.paddingMedium

                BackgroundItem {
                    id: isoBtn
                    visible: !page.editingIso && page.quickMeter
                    width: isoPillBg.width
                    height: isoPillBg.height
                    highlightedColor: FiatLuxTheme.highlightWash
                    onClicked: isoMenu.show(isoBtn)
                    Rectangle {
                        id: isoPillBg
                        radius: height / 2
                        color: isoBtn.highlighted ? FiatLuxTheme.pillFillActive
                                                  : FiatLuxTheme.pillFill
                        border.color: FiatLuxTheme.pillBorder
                        border.width: 1
                        width: isoLbl.width + Theme.paddingLarge * 2
                        height: isoLbl.height + Theme.paddingMedium
                        Text {
                            id: isoLbl
                            anchors.centerIn: parent
                            text: "ISO " + page.iso
                            color: FiatLuxTheme.primaryText
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                }

                Row {
                    visible: page.editingIso
                    spacing: Theme.paddingSmall
                    TextField {
                        id: isoEditor
                        width: Theme.itemSizeMedium
                        text: page.iso.toString()
                        color: FiatLuxTheme.primaryText
                        inputMethodHints: Qt.ImhDigitsOnly
                        maximumLength: 5
                        validator: IntValidator { bottom: 1; top: 99999 }
                        onTextChanged: {
                            var n = parseInt(text)
                            if (!isNaN(n) && n > 0) page.iso = n
                        }
                        EnterKey.onClicked: {
                            page.editingIso = false
                            page.publishReading()
                        }
                    }
                    IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        icon.source: "image://theme/icon-m-accept"
                        onClicked: {
                            page.editingIso = false
                            page.publishReading()
                        }
                    }
                }

                // A camera with no film: the ISO is the film's, so ask for film.
                BackgroundItem {
                    id: loadFilmBtn
                    visible: !page.quickMeter && page.rollId < 0
                    width: loadFilmBg.width
                    height: loadFilmBg.height
                    highlightedColor: FiatLuxTheme.highlightWash
                    onClicked: pageStack.push(Qt.resolvedUrl("AddRollPage.qml"), { presetCameraId: page.cameraId })
                    Rectangle {
                        id: loadFilmBg
                        radius: height / 2
                        color: loadFilmBtn.highlighted ? FiatLuxTheme.pillFillActive
                                                       : FiatLuxTheme.pillFill
                        border.color: FiatLuxTheme.pillBorderActive
                        border.width: 1
                        width: loadFilmLbl.width + Theme.paddingLarge * 2
                        height: loadFilmLbl.height + Theme.paddingMedium
                        Text {
                            id: loadFilmLbl
                            anchors.centerIn: parent
                            text: qsTr("load film")
                            color: FiatLuxTheme.accent
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: FiatLuxTheme.serif
                            font.italic: true
                        }
                    }
                }

                BackgroundItem {
                    id: lensBtn
                    visible: page.lens.length > 0
                    width: lensPillBg.width
                    height: lensPillBg.height
                    highlightedColor: FiatLuxTheme.highlightWash
                    onClicked: {
                        if (page.compatLenses.length <= 1) return
                        var arr = []
                        for (var i = 0; i < page.compatLenses.length; i++) {
                            arr.push(page.compatLenses[i].name)
                        }
                        lensMenu.items = arr
                        lensMenu.show(lensBtn)
                    }
                    Rectangle {
                        id: lensPillBg
                        radius: height / 2
                        color: lensBtn.highlighted ? FiatLuxTheme.pillFillActive
                                                   : FiatLuxTheme.pillFill
                        border.color: FiatLuxTheme.pillBorder
                        border.width: 1
                        width: Math.min(lensLbl.implicitWidth + Theme.paddingLarge * 2,
                                        page.width - 2 * Theme.horizontalPageMargin - 160)
                        height: lensLbl.height + Theme.paddingMedium
                        Text {
                            id: lensLbl
                            anchors.centerIn: parent
                            width: parent.width - Theme.paddingLarge * 2
                            text: page.lens
                            color: FiatLuxTheme.primaryText
                            font.pixelSize: Theme.fontSizeSmall
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            // ---- what this meter is ----
            Column {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                spacing: 0

                Label {
                    width: parent.width
                    text: meter.spot ? qsTr("reflected \u00b7 spot") : qsTr("reflected \u00b7 whole frame")
                    font.pixelSize: Theme.fontSizeExtraSmall
                    font.bold: true
                    color: FiatLuxTheme.accent
                }

                Label {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: qsTr("Metered through the camera, like a reflected meter. Tap the viewfinder to meter a spot; press and hold to go back to the whole frame.")
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: FiatLuxTheme.secondaryText
                }
            }

            // ---- measure ----
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
                           ? Qt.darker(FiatLuxTheme.accent, 1.2)
                           : FiatLuxTheme.accent
                    Row {
                        anchors.centerIn: parent
                        spacing: Theme.paddingMedium
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.evLocked ? qsTr("remeasure") : qsTr("measure")
                            color: FiatLuxTheme.markOn(FiatLuxTheme.accent)
                            font.pixelSize: Theme.fontSizeMedium
                            font.family: FiatLuxTheme.serif
                            font.italic: true
                            font.bold: true
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: page.evLocked
                            text: "EV " + page.ev.toFixed(1)
                            color: FiatLuxTheme.markOn(FiatLuxTheme.accent)
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                }
            }

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
            // No icon. image://theme/ icons are drawn in the ambience's primary
            // colour, which under Fiat colours on a dark ambience is white on a
            // white button. The word does the job on its own.
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
                    color: captureBtn.highlighted ? FiatLuxTheme.pillFillActive
                                                  : FiatLuxTheme.card
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
        items: [25,50,64,100,125,160,200,250,320,400,500,640,800,1000,1250,1600,2500,3200,6400,"Custom\u2026"]
        onPicked: function(idx) {
            if (typeof items[idx] === "string") {
                page.editingIso = true
            } else {
                page.iso = items[idx]
                page.publishReading()
            }
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
