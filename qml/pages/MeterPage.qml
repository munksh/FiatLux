import QtQuick 2.0
import Sailfish.Silica 1.0
import QtMultimedia 5.0
import QtSensors 5.2
import "../Storage.js" as Storage
import ".." 1.0

Page {
    id: page
    allowedOrientations: Orientation.Portrait
    background: Rectangle { color: FiatLuxTheme.deepBg }

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
    property string picturesDir: "/home/defaultuser/Pictures"

    // Sensor rotation for the viewfinder. Try 0 / 90 / 180 / 270 / -90.
    property int viewfinderOrientation: 0

    // Light meter calibration, in stops. Adjust against a known-good meter.
    property real evCalibration: 0.0
    property real lastLux: -1

    // Where the scroller lands after a measurement — handheld default 1/125 s.
    property real preferredSpeed: 1/125

    readonly property var defaultApertures: ["1","1.4","1.7","2","2.8","4","5.6","8","11","16","22"]
    readonly property var defaultSpeeds: ["1/1000","1/500","1/250","1/125","1/60","1/30","1/15","1/8","1/4","1/2","1\""]

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

    // Incident metering from the ambient light sensor.
    //   EV100 = log2(lux / 2.5)     (C = 250, standard incident constant)
    function measure() {
        var lux = page.lastLux

        console.log("measure() — lux:", lux)

        if (lux !== undefined && lux > 0) {
            ev = Math.log(lux / 2.5) / Math.LN2 + evCalibration
            evLocked = true
            exposureList.currentIndex = suggestIndex()
        } else {
            console.log("measure() — no light sensor reading yet")
        }
    }

    function currentAperture() {
        if (!apertures || apertures.length === 0) return "-"
        return apertures[exposureList.currentIndex] || "-"
    }

    function currentSpeed() {
        if (!shutterSpeeds || shutterSpeeds.length === 0) return "-"
        return shutterSpeeds[calcShutterIndex(exposureList.currentIndex)] || "-"
    }

    function logShot(photoPath) {
        if (rollId < 0) return
        Storage.addShot(rollId, new Date().toISOString(), ev,
                        currentAperture(), currentSpeed(), iso, photoPath || "")
        shotCount = Storage.shotCountForRoll(rollId)
        shotFlash.restart()
    }

    function capture() {
        if (camera.availability !== Camera.Available) return
        camera.imageCapture.captureToLocation(picturesDir)
    }

    Camera {
        id: camera
        captureMode: Camera.CaptureStillImage
        imageCapture {
            onImageSaved: {
                shotFlash.restart()
                page.logShot(path)
            }
            onCaptureFailed: console.log("capture failed:", message)
        }
    }

    LightSensor {
        id: lightSensor
        active: Qt.application.state === Qt.ApplicationActive
        onReadingChanged: page.lastLux = reading.illuminance
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: contentColumn.height

        PullDownMenu {
            backgroundColor: FiatLuxTheme.surface
            highlightColor: FiatLuxTheme.amber

            MenuItem {
                text: FiatLuxTheme.ambient ? "Fiat Lux colours" : "Follow ambience"
                color: FiatLuxTheme.primaryText
                onClicked: FiatLuxTheme.setAmbient(!FiatLuxTheme.ambient)
            }
            MenuItem {
                visible: rollId >= 0
                text: "Close roll"
                color: FiatLuxTheme.primaryText
                onClicked: {
                    Storage.closeRoll(rollId)
                    app.reloadRolls()
                    loadQuick()
                }
            }
            MenuItem {
                text: "New roll"
                color: FiatLuxTheme.primaryText
                onClicked: pageStack.push(Qt.resolvedUrl("AddRollPage.qml"), { returnToMeter: true })
            }
            MenuItem {
                text: "Film stocks"
                color: FiatLuxTheme.primaryText
                onClicked: pageStack.push(Qt.resolvedUrl("FilmPage.qml"))
            }
            MenuItem {
                text: "Lenses"
                color: FiatLuxTheme.primaryText
                onClicked: pageStack.push(Qt.resolvedUrl("LensesPage.qml"))
            }
            MenuItem {
                text: "Cameras"
                color: FiatLuxTheme.primaryText
                onClicked: pageStack.push(Qt.resolvedUrl("CamerasPage.qml"))
            }
        }

        Column {
            id: contentColumn
            width: page.width
            spacing: Theme.paddingMedium

            // Clearance for the system status bar / notch
            Item { width: 1; height: Theme.paddingLarge }

            // Top bar
            Item {
                width: parent.width; height: Theme.itemSizeLarge
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    text: "fiat lux"
                    color: FiatLuxTheme.primaryText
                    font.pixelSize: Theme.fontSizeLarge
                    font.family: FiatLuxTheme.serif; font.italic: true
                }
                BackgroundItem {
                    id: sourcePill
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    width: pillRow.width + Theme.paddingLarge * 2
                    height: Theme.itemSizeSmall
                    onClicked: {
                        var arr = ["Quick Meter"]
                        for (var i = 0; i < app.cameraModel.count; i++)
                            arr.push(app.cameraModel.get(i).name)
                        sourceMenu.items = arr
                        sourceMenu.show(sourcePill)
                    }
                    Rectangle {
                        anchors.fill: parent; radius: height / 2
                        color: sourcePill.highlighted ? FiatLuxTheme.amberMed : FiatLuxTheme.surface
                        border.color: FiatLuxTheme.amber; border.width: 1
                    }
                    Row {
                        id: pillRow
                        anchors.centerIn: parent; spacing: Theme.paddingSmall
                        Text {
                            text: rollId >= 0 ? sourceLabel + " · " + shotCount + "fr" : sourceLabel
                            color: FiatLuxTheme.primaryText
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: FiatLuxTheme.serif; font.italic: true
                        }
                        Text {
                            text: "▾"; color: FiatLuxTheme.amber
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                }
            }

            // Viewfinder with burn-in HUD
            Rectangle {
                id: viewfinder
                width: page.width; height: page.width
                color: "black"; clip: true

                VideoOutput {
                    id: vo
                    source: camera
                    anchors.centerIn: parent
                    // Manual "crop to fill": overfill the square, parent clips.
                    property real ar: sourceRect.height > 0
                                      ? sourceRect.width / sourceRect.height : 1
                    width:  ar >= 1 ? parent.height * ar : parent.width
                    height: ar >= 1 ? parent.height : parent.width / ar
                    fillMode: VideoOutput.PreserveAspectFit
                    orientation: page.viewfinderOrientation
                    visible: camera.availability === Camera.Available
                }

                Column {
                    anchors.centerIn: parent
                    visible: camera.availability !== Camera.Available
                    spacing: Theme.paddingMedium
                    Canvas {
                        width: 64; height: 40
                        anchors.horizontalCenter: parent.horizontalCenter
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            ctx.beginPath(); ctx.arc(32, 40, 32, Math.PI, 0)
                            ctx.fillStyle = "#F4EED8"; ctx.fill()
                            ctx.beginPath(); ctx.ellipse(0, 34, 64, 12)
                            ctx.fillStyle = "#D8CEAE"; ctx.fill()
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "camera not available"
                        color: FiatLuxTheme.secondaryText
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: FiatLuxTheme.serif; font.italic: true
                    }
                }

                Rectangle {
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: hudRow.height + Theme.paddingMedium * 2
                    color: Qt.rgba(0, 0, 0, 0.65)
                    Row {
                        id: hudRow; anchors.centerIn: parent
                        spacing: Theme.paddingLarge
                        Text {
                            // Comma operator: read the dependencies, show the last value.
                            text: (page.apertures,
                                   exposureList.currentIndex,
                                   "f/" + currentAperture())
                            color: "white"
                            font.pixelSize: Theme.fontSizeMedium
                        }
                        Text {
                            text: (page.iso, page.ev, page.shutterSpeeds,
                                   exposureList.currentIndex, currentSpeed())
                            color: FiatLuxTheme.amber
                            font.pixelSize: Theme.fontSizeMedium
                        }
                        Text {
                            text: "ISO " + iso
                            color: "white"
                            font.pixelSize: Theme.fontSizeMedium
                        }
                    }
                }

                Rectangle {
                    id: shotFlash; anchors.fill: parent
                    color: "#F4EED8"; opacity: 0
                    function restart() { flashAnim.restart() }
                    NumberAnimation {
                        id: flashAnim; target: shotFlash; property: "opacity"
                        from: 0.6; to: 0.0; duration: 350
                    }
                }
            }

            // Exposure scroller
            Rectangle {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                height: Theme.itemSizeLarge * 2
                radius: Theme.paddingLarge * 1.5
                color: FiatLuxTheme.surface
                border.color: evLocked ? FiatLuxTheme.amber : FiatLuxTheme.rim
                border.width: evLocked ? 2 : 1
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
                    delegate: Item {
                        width: Theme.itemSizeHuge; height: exposureList.height
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
                            color: FiatLuxTheme.amberSoft
                            border.color: FiatLuxTheme.amber; border.width: 1
                            visible: isCenter
                        }
                        Column {
                            anchors.centerIn: parent; spacing: Theme.paddingSmall
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: (shutterSpeeds && shutterSpeeds.length > shutterIdx)
                                      ? shutterSpeeds[shutterIdx] : "-"
                                color: isCenter ? FiatLuxTheme.amber : FiatLuxTheme.secondaryText
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

            // ISO + lens row
            Row {
                x: Theme.horizontalPageMargin; spacing: Theme.paddingMedium

                BackgroundItem {
                    id: isoBtn
                    visible: !editingIso
                    width: isoPillBg.width; height: isoPillBg.height
                    onClicked: isoMenu.show(isoBtn)
                    Rectangle {
                        id: isoPillBg; radius: height / 2
                        color: isoBtn.highlighted ? FiatLuxTheme.amberMed : FiatLuxTheme.surface
                        border.color: FiatLuxTheme.rim; border.width: 1
                        width: isoLbl.width + Theme.paddingLarge * 2
                        height: isoLbl.height + Theme.paddingMedium
                        Text {
                            id: isoLbl; anchors.centerIn: parent
                            text: "ISO " + iso
                            color: FiatLuxTheme.primaryText
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                }

                Row {
                    visible: editingIso; spacing: Theme.paddingSmall
                    TextField {
                        id: isoEditor; width: Theme.itemSizeMedium
                        text: iso.toString(); color: FiatLuxTheme.primaryText
                        inputMethodHints: Qt.ImhDigitsOnly; maximumLength: 5
                        validator: IntValidator { bottom: 1; top: 99999 }
                        onTextChanged: { var n = parseInt(text); if (!isNaN(n) && n > 0) iso = n }
                        EnterKey.onClicked: editingIso = false
                    }
                    IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        icon.source: "image://theme/icon-m-accept"
                        onClicked: editingIso = false
                    }
                }

                BackgroundItem {
                    id: lensBtn
                    visible: lens.length > 0
                    width: lensPillBg.width; height: lensPillBg.height
                    onClicked: {
                        if (compatLenses.length <= 1) return
                        var arr = []
                        for (var i = 0; i < compatLenses.length; i++) arr.push(compatLenses[i].name)
                        lensMenu.items = arr
                        lensMenu.show(lensBtn)
                    }
                    Rectangle {
                        id: lensPillBg; radius: height / 2
                        color: lensBtn.highlighted ? FiatLuxTheme.amberMed : FiatLuxTheme.surface
                        border.color: FiatLuxTheme.rim; border.width: 1
                        width: Math.min(lensLbl.implicitWidth + Theme.paddingLarge * 2,
                                        page.width - 2 * Theme.horizontalPageMargin - 160)
                        height: lensLbl.height + Theme.paddingMedium
                        Text {
                            id: lensLbl; anchors.centerIn: parent
                            width: parent.width - Theme.paddingLarge * 2
                            text: lens; color: FiatLuxTheme.primaryText
                            font.pixelSize: Theme.fontSizeSmall; elide: Text.ElideRight
                        }
                    }
                }
            }

            // Measure button
            BackgroundItem {
                id: measureBtn
                width: parent.width; height: Theme.itemSizeLarge
                onClicked: page.measure()
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    height: Theme.itemSizeMedium; radius: Theme.paddingLarge
                    color: measureBtn.highlighted ? FiatLuxTheme.amberStrong : FiatLuxTheme.amber
                    Row {
                        anchors.centerIn: parent; spacing: Theme.paddingMedium
                        Text {
                            text: evLocked ? "remeasure" : "measure"
                            color: FiatLuxTheme.onAccent
                            font.pixelSize: Theme.fontSizeMedium
                            font.family: FiatLuxTheme.serif; font.italic: true; font.bold: true
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            visible: evLocked; text: "EV " + ev.toFixed(1)
                            color: FiatLuxTheme.onAccent
                            font.pixelSize: Theme.fontSizeSmall
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }

            // Log / capture row
            Row {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                spacing: Theme.paddingMedium

                BackgroundItem {
                    id: logBtn
                    visible: rollId >= 0
                    width: captureBtn.visible ? (parent.width - parent.spacing) / 2 : parent.width
                    height: Theme.itemSizeMedium
                    onClicked: page.logShot("")
                    Rectangle {
                        anchors.fill: parent; radius: Theme.paddingLarge
                        color: logBtn.highlighted ? FiatLuxTheme.amberSoft : FiatLuxTheme.surface
                        border.color: FiatLuxTheme.rim; border.width: 1
                        Text {
                            anchors.centerIn: parent; text: "log shot"
                            color: FiatLuxTheme.primaryText
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: FiatLuxTheme.serif; font.italic: true
                        }
                    }
                }

                BackgroundItem {
                    id: captureBtn
                    visible: camera.availability === Camera.Available
                    width: logBtn.visible ? (parent.width - parent.spacing) / 2 : parent.width
                    height: Theme.itemSizeMedium
                    onClicked: page.capture()
                    Rectangle {
                        anchors.fill: parent; radius: Theme.paddingLarge
                        color: captureBtn.highlighted ? FiatLuxTheme.amberSoft : FiatLuxTheme.surface
                        border.color: FiatLuxTheme.amber; border.width: 1
                        Row {
                            anchors.centerIn: parent; spacing: Theme.paddingSmall
                            Image {
                                anchors.verticalCenter: parent.verticalCenter
                                source: "image://theme/icon-m-camera"
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: rollId >= 0 ? "capture & log" : "capture"
                                color: FiatLuxTheme.primaryText
                                font.pixelSize: Theme.fontSizeSmall
                                font.family: FiatLuxTheme.serif; font.italic: true
                            }
                        }
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
            if (idx === 0) page.loadQuick()
            else page.loadCamera(app.cameraModel.get(idx - 1).id)
        }
    }

    PillMenu {
        id: isoMenu
        items: [25,50,64,100,125,160,200,250,320,400,500,640,800,1000,1250,1600,2500,3200,6400,"Custom…"]
        onPicked: function(idx) {
            if (typeof items[idx] === "string") page.editingIso = true
            else page.iso = items[idx]
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
