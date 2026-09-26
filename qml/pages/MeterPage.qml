import QtQuick 2.0
import Sailfish.Silica 1.0
import se.munkstolen.fiatlux 1.0
import Nemo.Configuration 1.0
import "../Storage.js" as Storage
import "../Gear.js" as Gear
import ".." 1.0
import "../components"

// The meter. One screen that never scrolls: the viewfinder, the dial, the
// camera, and the two buttons. It only grows when the camera's dropdown is
// open under its line.

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
    property var compatLenses: []
    property int lensIndex: 0
    property string lens: ""
    property var apertures: []
    property var shutterSpeeds: []
    property real ev: 8.0
    property bool evLocked: false
    property int shotCount: 0

    // The camera being metered for (-1 = Quick Meter) and the film in it.
    // Only Quick Meter lets you pick an ISO; a camera meters its film's.
    property int cameraId: -1
    property string filmLabel: ""
    property string cameraApertures: ""
    readonly property bool quickMeter: page.cameraId < 0

    // The aperture on the dial. The speed is the dial's own business.
    property int apIndex: 0
    onApIndexChanged: if (dial.apIndex !== apIndex) dial.apIndex = apIndex

    property var sourceChoices: []

    function refreshSources() {
        var arr = [{ id: -1, label: qsTr("Quick Meter") }]
        for (var i = 0; i < app.cameraModel.count; i++) {
            var c = app.cameraModel.get(i)
            var r = Storage.openRollForCamera(c.id)
            var film = r >= 0 ? Storage.getRoll(r) : null
            arr.push({ id: c.id, label: film ? c.name + "  ·  " + film.stockName : c.name })
        }
        sourceChoices = arr
    }

    // The reading stays: it is the light, not the camera. Only the pairs
    // change, to what this camera and its film can do.
    function chooseSource(id) {
        if (id < 0) page.loadQuick()
        else page.loadCamera(id)
    }

    function chooseIso() {
        var d = pageStack.push(Qt.resolvedUrl("PlateDialog.qml"),
                               { kind: "iso", selected: ["" + page.iso], owner: qsTr("Quick Meter") })
        d.accepted.connect(function() {
            var n = parseInt(d.selected[0])
            if (n > 0) {
                page.iso = n
                page.publishReading()
            }
        })
    }

    function paint() { FiatLuxTheme.applyPalette(page) }
    Connections {
        target: FiatLuxTheme
        onAmbientChanged: page.paint()
    }

    // Raise when the introduction changes enough to be worth showing again.
    readonly property int introVersion: 2
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
        if (status === PageStatus.Active) {
            page.paint()
            page.refreshSources()
            page.refreshLenses()
        }
        if (status === PageStatus.Active && !page.introChecked) {
            page.introChecked = true
            introTimer.start()
        }
    }

    // Rotation of the Camera2 frames on screen. Try 0 / 90 / 180 / 270.
    property int viewfinderOrientation: 90

    // Where the dial lands after a measurement -- handheld, 1/125 s.
    property real preferredSpeed: 1/125

    readonly property var defaultApertures: ["1", "1.4", "2", "2.8", "4", "5.6", "8", "11", "16", "22"]
    readonly property var defaultSpeeds: ["1/1000", "1/500", "1/250", "1/125", "1/60", "1/30", "1/15", "1/8", "1/4", "1/2", "1\""]

    // ---- calibration -----------------------------------------------------
    //
    // In stops, in dconf, so the calibrate page and the meter read the same
    // number. The guard matters -- a dconf value reads back undefined before
    // the key exists, and undefined arithmetic gives NaN.
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
        // Nothing has been metered, so there is nothing to show.
        if (!page.evLocked) return
        if (page.currentApertureText === "-" || page.currentSpeedText === "-") return
        cfgAperture.value = page.currentApertureText
        cfgSpeed.value = page.currentSpeedText
        cfgCamera.value = page.sourceLabel
        cfgIso.value = page.iso
        cfgFilm.value = page.rollId >= 0 ? page.filmLabel : ""
    }

    readonly property string currentApertureText: {
        var a = page.apertures
        var i = page.apIndex
        if (!a || i < 0 || i >= a.length) return "-"
        return a[i]
    }

    readonly property string currentSpeedText: {
        var s = page.shutterSpeeds
        var k = dial.pickedSpeed
        if (!s || k < 0 || k >= s.length) return "-"
        return s[k]
    }

    // EV at the film's speed, which is what places the speeds on the dial.
    readonly property real evIso: page.ev + Math.log(page.iso / 100) / Math.LN2

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
        compatLenses = cameraType !== 0 && mount.length > 0 ? Storage.lensesForMount(mount) : []
        lensIndex = lensIndexFor(rememberedLens(c.id))
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

    // The lens is chosen on its own line under the camera, and remembered:
    // on the roll when there is film in the camera, per camera when not.
    ConfigurationValue { id: cfgCameraLens; key: "/apps/harbour-fiatlux/cameraLens"; defaultValue: "{}" }

    function rememberedLens(camId) {
        try {
            var map = JSON.parse(cfgCameraLens.value || "{}")
            return map["" + camId] !== undefined ? map["" + camId] : -1
        } catch (e) {
            return -1
        }
    }

    function lensIndexFor(lensId) {
        for (var i = 0; i < compatLenses.length; i++)
            if (compatLenses[i].id === lensId) return i
        return 0
    }

    function chooseLens(i) {
        if (i < 0 || i >= compatLenses.length) return
        lensIndex = i
        applyLens()
        var id = compatLenses[i].id
        if (rollId >= 0) {
            Storage.setRollLens(rollId, id)
            app.reloadRolls()
        } else if (cameraId >= 0) {
            var map = {}
            try { map = JSON.parse(cfgCameraLens.value || "{}") } catch (e) { map = {} }
            map["" + cameraId] = id
            cfgCameraLens.value = JSON.stringify(map)
        }
    }

    // Back on the meter after adding or editing lenses: pick up the new list
    // and keep the lens that was chosen.
    function refreshLenses() {
        if (cameraType === 0 || mount.length === 0) return
        var current = compatLenses.length > 0 ? compatLenses[Math.min(lensIndex, compatLenses.length - 1)].id
                                              : (rollId >= 0 ? -1 : rememberedLens(cameraId))
        if (rollId >= 0 && current < 0) {
            var r = Storage.getRoll(rollId)
            if (r) current = r.lensId
        }
        compatLenses = Storage.lensesForMount(mount)
        lensIndex = lensIndexFor(current)
        applyLens()
    }

    // Where the apertures and speeds come from:
    //   fixed lens      both from the camera
    //   otherwise       apertures from the lens; speeds from the lens, else
    //                   the body, else the defaults (the data is incomplete)
    function applyLens() {
        var bSpeeds = Gear.splitList(bodySpeeds)
        var ap, sp
        if (cameraType === 0 && cameraApertures.length > 0) {
            lens = ""
            ap = Gear.splitList(cameraApertures)
            sp = bSpeeds
        } else if (compatLenses.length > 0) {
            var l = compatLenses[Math.min(lensIndex, compatLenses.length - 1)]
            lens = l.name
            ap = Gear.splitList(l.apertures)
            var lSpeeds = Gear.splitList(l.speeds)
            sp = lSpeeds.length > 0 ? lSpeeds : bSpeeds
        } else {
            lens = ""
            ap = []
            sp = bSpeeds
        }
        if (ap.length === 0) ap = defaultApertures.slice()
        if (sp.length === 0) sp = defaultSpeeds.slice()
        var oldAperture = currentApertureText
        dial.chosenSpeed = -1
        apertures = Gear.sortApertures(ap)
        shutterSpeeds = Gear.speedsForStorage(sp)
        if (evLocked) {
            apIndex = suggestIndex()
        } else {
            var keep = apertures.indexOf(oldAperture)
            apIndex = keep >= 0 ? keep : Math.max(0, apertures.indexOf("8") >= 0 ? apertures.indexOf("8")
                                                                                   : Math.floor(apertures.length / 2))
        }
        publishReading()
    }

    // ---- the exposure arithmetic -----------------------------------------

    // The aperture whose nearest speed is closest to a handheld 1/125.
    function suggestIndex() {
        var a = page.apertures
        var s = page.shutterSpeeds
        if (!a || a.length === 0 || !s || s.length === 0) return 0
        var best = 0
        var diff = Infinity
        for (var i = 0; i < a.length; i++) {
            var n = parseFloat(a[i])
            var wanted = (n * n) / Math.pow(2, page.evIso)
            var k = -1, dk = Infinity
            for (var j = 0; j < s.length; j++) {
                var t = Gear.parseSpeed(s[j])
                if (t === null || !(t > 0)) continue
                var d0 = Math.abs(Math.log(t / wanted) / Math.LN2)
                if (d0 < dk) { dk = d0; k = j }
            }
            if (k < 0) continue
            var sv = Gear.parseSpeed(s[k])
            // Prefer a pairing that is close to exact, then near 1/125.
            var d = dk * 2 + Math.abs(Math.log(sv / page.preferredSpeed) / Math.LN2)
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

    function measure() {
        if (!meter.metered) {
            page.note(meter.errorString !== "" ? meter.errorString
                                               : qsTr("no reading from the camera yet"))
            return
        }
        page.ev = meter.ev100 + page.evCalibration
        page.evLocked = true
        dial.chosenSpeed = -1
        page.apIndex = page.suggestIndex()
        page.publishReading()
    }

    // What the line under the dial says.
    readonly property string readout: {
        if (!page.evLocked) return ""
        if (dial.pickedSpeed < 0) return ""
        var d = dial.diffStops
        var t = Gear.thirds(d)
        var s = t === "0" ? qsTr("exact")
                          : (d > 0 ? "+" : "−") + t + " " + (d > 0 ? qsTr("over") : qsTr("under"))
        if (dial.deliberate) return s + "  ·  " + qsTr("chosen")
        if (Math.abs(d) >= 1) {
            var n = parseFloat(page.currentApertureText)
            var exact = (n * n) / Math.pow(2, page.evIso)
            if (d < 0 && page.shutterSpeeds.indexOf("B") !== -1)
                return s + "  ·  " + qsTr("or B for %1").arg(Gear.formatSeconds(exact))
            return s + "  ·  " + (d < 0 ? qsTr("no longer speed") : qsTr("no faster speed"))
        }
        return s
    }
    readonly property bool readoutWarns: page.evLocked && !dial.deliberate && Math.abs(dial.diffStops) >= 1

    // ---- notes, shown on the viewfinder for a moment ----

    property string noteText: ""
    function note(t) {
        page.noteText = t
        noteTimer.restart()
    }
    Timer {
        id: noteTimer
        interval: 3500
        onTriggered: page.noteText = ""
    }

    // ---- logging a shot ---------------------------------------------------
    //
    // A real photo from the camera, cropped to the square you were looking
    // at, with the strip burnt in: the pair, the film speed, and which camera,
    // film and frame. Saved in Pictures/FiatLux. It is a note about what you
    // metered; the photograph is on film.

    property var pendingShot: null

    function stripDetail() {
        if (page.quickMeter) return ""
        if (page.rollId >= 0)
            return page.sourceLabel + "  ·  " + page.filmLabel + "  ·  " + qsTr("frame %1").arg(page.shotCount + 1)
        return page.sourceLabel + "  ·  " + qsTr("no film")
    }

    function logShot() {
        if (meter.capturing) return
        page.pendingShot = { rollId: page.rollId, ev: page.ev, aperture: page.currentApertureText,
                             speed: page.currentSpeedText, iso: page.iso }
        shotFlash.restart()
        if (!meter.captureShot("f/" + page.currentApertureText, page.currentSpeedText,
                               "ISO " + page.iso, page.stripDetail())) {
            page.recordShot("")
            page.note(qsTr("could not take the picture — logged without it"))
        }
    }

    function recordShot(path) {
        var s = page.pendingShot
        page.pendingShot = null
        if (!s || s.rollId < 0 || s.rollId !== page.rollId) return false
        Storage.addShot(s.rollId, new Date().toISOString(), s.ev, s.aperture, s.speed, s.iso, path || "")
        page.shotCount = Storage.shotCountForRoll(s.rollId)
        return true
    }

    Connections {
        target: meter
        onShotSaved: {
            var logged = page.recordShot(path)
            if (logged) page.note(qsTr("frame %1 logged").arg(page.shotCount))
            else page.note(qsTr("saved in Pictures/FiatLux — load film to log frames"))
        }
        onShotFailed: {
            var logged = page.recordShot("")
            page.note(logged ? qsTr("frame %1 logged, without the picture").arg(page.shotCount)
                             : qsTr("could not save the picture: %1").arg(reason))
        }
    }

    // ---- is the app actually in front of you? -----------------------------
    //
    // POLLED, not bound. Qt.application.state is correct when you read it, but
    // on Sailfish its change signal does not reliably arrive -- a binding on
    // it latches to whatever was true at load.

    property int appState: Qt.ApplicationActive
    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: page.appState = Qt.application.state
    }

    readonly property bool cameraLive: meter.running && meter.hasFrame

    PaperBackground { }

    SilicaFlickable {
        id: flick
        anchors.fill: parent
        contentHeight: Math.max(height, column.height)

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
                    page.refreshSources()
                }
            }
            MenuItem {
                text: qsTr("Loaded film")
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
            id: column
            width: page.width

            // ---- top bar: the wordmark, and the film speed opposite ----
            Item {
                id: topBar
                width: parent.width
                height: FiatLuxTheme.statusRowCenter + wordmark.height / 2 + Theme.paddingMedium

                Text {
                    id: wordmark
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.horizontalPageMargin
                    y: Math.max(0, FiatLuxTheme.statusRowCenter - height / 2)
                    text: "fiat lux"
                    color: FiatLuxTheme.primaryText
                    font.pixelSize: Theme.fontSizeLarge
                    font.family: FiatLuxTheme.serif
                    font.italic: true
                }

                // Only Quick Meter lets you choose; with a film loaded, the
                // film decides, and the corner only says what it is.
                MouseArea {
                    id: isoCorner
                    anchors.right: parent.right
                    width: isoRow.width + Theme.horizontalPageMargin * 2
                    height: Theme.itemSizeSmall
                    y: FiatLuxTheme.statusRowCenter - height / 2
                    enabled: page.quickMeter
                    onClicked: page.chooseIso()

                    Rectangle {
                        anchors.fill: parent
                        color: FiatLuxTheme.highlightWash
                        visible: isoCorner.pressed && isoCorner.containsMouse
                    }

                    Row {
                        id: isoRow
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.paddingSmall
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "ISO " + page.iso
                            color: page.quickMeter ? FiatLuxTheme.primaryText : FiatLuxTheme.secondaryText
                            font.pixelSize: Theme.fontSizeMedium
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: page.quickMeter
                            text: "▾"
                            color: FiatLuxTheme.accent
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                }
            }

            // ---- viewfinder ----
            //
            // The one fixed dark surface in the app: it stands in for a camera
            // feed. Square, as wide as the screen -- unless the screen is too
            // short for everything below it, then as big as fits.
            Rectangle {
                id: viewfinder
                readonly property real room: page.height - topBar.height - dial.height - readoutLabel.height
                                             - rule.height - cameraLine.contentHeight
                                             - (lensLine.visible ? lensLine.contentHeight : 0) - measureBtn.height
                                             - logBtn.height - Theme.paddingLarge * 2
                width: Math.max(Theme.itemSizeHuge * 2, Math.min(page.width, room))
                height: width
                anchors.horizontalCenter: parent.horizontalCenter
                color: FiatLuxTheme.viewfinderBg
                clip: true

                Camera2Meter {
                    id: meter
                    anchors.fill: parent
                    fill: true
                    photos: true
                    orientation: page.viewfinderOrientation
                    active: page.status === PageStatus.Active
                            && page.appState === Qt.ApplicationActive
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
                // While the camera is down, a tap tries again.
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (!page.cameraLive) {
                            meter.restart()
                            return
                        }
                        spotMark.x = mouse.x - spotMark.width / 2
                        spotMark.y = mouse.y - spotMark.height / 2
                        meter.meterAt(mouse.x / width, mouse.y / height)
                    }
                    onPressAndHold: meter.meterWholeFrame()
                }

                // Waking, or what went wrong. Nothing technical while it is
                // only starting; the helper's own words only once it has
                // stopped trying.
                Column {
                    anchors.centerIn: parent
                    width: parent.width - Theme.horizontalPageMargin * 2
                    spacing: Theme.paddingSmall
                    visible: !page.cameraLive

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: meter.errorString !== "" ? qsTr("the camera would not start") : qsTr("waking the camera")
                        color: FiatLuxTheme.viewfinderText
                        opacity: 0.75
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: FiatLuxTheme.serif
                        font.italic: true
                    }
                    Text {
                        visible: meter.errorString !== ""
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        maximumLineCount: 4
                        elide: Text.ElideRight
                        text: meter.errorString + "\n" + qsTr("tap to try again")
                        color: FiatLuxTheme.viewfinderText
                        opacity: 0.45
                        font.pixelSize: Theme.fontSizeExtraSmall
                    }
                }

                // A moment's note: frame logged, picture saved.
                Rectangle {
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.topMargin: Theme.paddingMedium
                    width: Math.min(parent.width - Theme.paddingLarge * 2, noteLabel.implicitWidth + Theme.paddingLarge * 2)
                    height: noteLabel.height + Theme.paddingSmall * 2
                    radius: Theme.paddingSmall
                    color: Qt.rgba(0, 0, 0, 0.6)
                    opacity: page.noteText !== "" ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { FadeAnimation { } }
                    Text {
                        id: noteLabel
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, parent.parent.width - Theme.paddingLarge * 4)
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                        text: page.noteText
                        color: FiatLuxTheme.viewfinderText
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
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: Theme.paddingLarge
                            Text {
                                text: "f/" + page.currentApertureText
                                color: FiatLuxTheme.viewfinderText
                                font.pixelSize: Theme.fontSizeMedium
                            }
                            Text {
                                text: page.evLocked ? page.currentSpeedText : "–"
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
                            text: page.stripDetail()
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

            // ---- the dial ----
            ExposureDial {
                id: dial
                width: parent.width
                apertures: page.apertures
                speeds: page.shutterSpeeds
                evIso: page.evIso
                live: page.evLocked
                // Two-way, by hand: the page moves the dial after a
                // measurement, and your finger moves it the other way.
                onApIndexChanged: if (page.apIndex !== apIndex) page.apIndex = apIndex
                onChosen: page.publishReading()
            }

            Label {
                id: readoutLabel
                width: parent.width
                height: implicitHeight + Theme.paddingSmall
                horizontalAlignment: Text.AlignHCenter
                text: page.readout
                color: page.readoutWarns ? FiatLuxTheme.outOfRange : FiatLuxTheme.secondaryText
                font.pixelSize: Theme.fontSizeExtraSmall
            }

            Rectangle {
                id: rule
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                height: Math.max(1, Math.round(Theme.paddingSmall / 6))
                color: FiatLuxTheme.innerBorder
            }

            // ---- what is being metered ----
            //
            // The camera and its film, centred, with a dropdown under it the
            // way Mos does it. The last item is an action, not a choice.
            ListItem {
                id: cameraLine
                width: parent.width
                contentHeight: cameraCol.height + Theme.paddingMedium * 2
                highlightedColor: FiatLuxTheme.highlightWash
                onClicked: openMenu()

                Column {
                    id: cameraCol
                    anchors.centerIn: parent
                    width: parent.width - Theme.horizontalPageMargin * 2

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: Theme.paddingSmall
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, cameraCol.width - caret.width - Theme.paddingSmall)
                            truncationMode: TruncationMode.Fade
                            text: page.quickMeter ? qsTr("Quick Meter")
                                  : page.rollId >= 0 ? page.sourceLabel + "  ·  " + page.filmLabel
                                  : page.sourceLabel + "  ·  " + qsTr("no film")
                            color: FiatLuxTheme.primaryText
                            font.pixelSize: Theme.fontSizeMedium
                            font.family: FiatLuxTheme.serif
                            font.italic: true
                        }
                        Label {
                            id: caret
                            anchors.verticalCenter: parent.verticalCenter
                            text: "▾"
                            color: FiatLuxTheme.accent
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                }

                menu: ContextMenu {
                    highlightColor: FiatLuxTheme.accent
                    Repeater {
                        model: page.sourceChoices
                        MenuItem {
                            text: modelData.label
                            color: modelData.id === page.cameraId ? FiatLuxTheme.accent : FiatLuxTheme.primaryText
                            onClicked: page.chooseSource(modelData.id)
                        }
                    }
                    MenuItem {
                        text: page.cameraId >= 0 && page.rollId < 0 ? qsTr("load film into %1…").arg(page.sourceLabel)
                                                                     : qsTr("load film…")
                        color: FiatLuxTheme.accent
                        font.italic: true
                        font.family: FiatLuxTheme.serif
                        onClicked: pageStack.push(Qt.resolvedUrl("AddRollPage.qml"), { presetCameraId: page.cameraId })
                    }
                }
            }

            // ---- the lens, for a camera whose lens comes off ----
            ListItem {
                id: lensLine
                visible: page.cameraType !== 0 && page.cameraId >= 0
                width: parent.width
                contentHeight: lensRow.height + Theme.paddingSmall * 2
                highlightedColor: FiatLuxTheme.highlightWash
                onClicked: openMenu()

                Row {
                    id: lensRow
                    anchors.centerIn: parent
                    spacing: Theme.paddingSmall
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, lensLine.width - Theme.horizontalPageMargin * 2 - lensCaret.width)
                        truncationMode: TruncationMode.Fade
                        text: page.lens !== "" ? page.lens : qsTr("no lens for %1 yet").arg(page.mount)
                        color: FiatLuxTheme.secondaryText
                        font.pixelSize: Theme.fontSizeSmall
                    }
                    Label {
                        id: lensCaret
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u25be"
                        color: FiatLuxTheme.accent
                        font.pixelSize: Theme.fontSizeExtraSmall
                    }
                }

                menu: ContextMenu {
                    highlightColor: FiatLuxTheme.accent
                    Repeater {
                        model: page.compatLenses
                        MenuItem {
                            text: modelData.name
                            color: index === page.lensIndex ? FiatLuxTheme.accent : FiatLuxTheme.primaryText
                            onClicked: page.chooseLens(index)
                        }
                    }
                    MenuItem {
                        text: qsTr("add a lens\u2026")
                        color: FiatLuxTheme.accent
                        font.italic: true
                        font.family: FiatLuxTheme.serif
                        onClicked: pageStack.push(Qt.resolvedUrl("AddLensPage.qml"), { presetMount: page.mount })
                    }
                }
            }

            FiatButton {
                id: measureBtn
                text: page.evLocked ? qsTr("remeasure") : qsTr("measure")
                detail: page.evLocked ? "EV " + page.ev.toFixed(1) : ""
                onClicked: page.measure()
            }

            FiatButton {
                id: logBtn
                filled: false
                text: meter.capturing ? qsTr("taking the picture…") : qsTr("log shot")
                enabled: page.cameraLive && page.evLocked && !meter.capturing
                onClicked: page.logShot()
            }

            Item { width: 1; height: Theme.paddingLarge }
        }
    }
}
