import QtQuick 2.0
import Sailfish.Silica 1.0
import "../Storage.js" as Storage
import "../FilmCatalogue.js" as Catalogue
import ".." 1.0
import "../components"

// Load film: which camera, which film, and the speed you shoot it at. Loading
// a film into a camera closes whatever roll was in it before; that roll and
// its shots stay in the log.
//
// The film list folds away once a film is chosen, so the speed and the load
// button come up under it instead of below fifty other films.

Page {
    id: page
    allowedOrientations: Orientation.Portrait

    Rectangle {
        anchors.fill: parent
        z: -1
        visible: !FiatLuxTheme.ambient
        gradient: Gradient {
            GradientStop { position: 0.0; color: FiatLuxTheme.backgroundHigh }
            GradientStop { position: 1.0; color: FiatLuxTheme.backgroundLow }
        }
    }

    function paint() { FiatLuxTheme.applyPalette(page) }
    Connections {
        target: FiatLuxTheme
        onAmbientChanged: page.paint()
    }

    // Accepted from older call sites; the page always returns to the meter.
    property bool returnToMeter: true
    property int presetCameraId: -1

    property int cameraId: -1
    property int cameraType: -1
    property string cameraMount: ""
    property var compatLenses: []
    property int lensId: -1

    property var films: []
    property var film: null      // { id, name, boxIso }
    property string query: ""

    readonly property bool canLoad: film !== null && cameraId >= 0 && parseInt(isoField.text) > 0

    Component.onCompleted: {
        paint()
        refreshFilms()
        if (presetCameraId >= 0) chooseCamera(Storage.getCamera(presetCameraId))
        else if (app.cameraModel.count === 1) chooseCamera(app.cameraModel.get(0))
    }

    // Back from "add a film that isn't listed": pick up what was added.
    onStatusChanged: if (status === PageStatus.Active) refreshFilms()

    // A ComboBox takes its index from the menu items, which a Repeater only
    // creates after the model is set -- so the index is set a beat later.
    Timer {
        id: syncTimer
        interval: 0
        onTriggered: {
            for (var i = 0; i < app.cameraModel.count; i++) {
                if (app.cameraModel.get(i).id === page.cameraId) { cameraCombo.currentIndex = i; break }
            }
            var k = -1
            for (var j = 0; j < page.compatLenses.length; j++) {
                if (page.compatLenses[j].id === page.lensId) { k = j; break }
            }
            lensCombo.currentIndex = k
        }
    }

    function refreshFilms() {
        films = Storage.filmsForPicker(Catalogue.films)
    }

    function chooseCamera(c) {
        if (!c) return
        cameraId = c.id
        cameraType = c.type
        cameraMount = c.mount || ""
        compatLenses = cameraType !== 0 && cameraMount.length > 0 ? Storage.lensesForMount(cameraMount) : []
        lensId = compatLenses.length === 1 ? compatLenses[0].id : -1
        syncTimer.restart()
    }

    function chooseFilm(f) {
        film = { id: f.id, name: f.name, boxIso: f.boxIso }
        isoField.text = f.boxIso.toString()
        query = ""
        searchField.text = ""
        searchField.focus = false
    }

    function toggleFavourite(f) {
        var id = f.id >= 0 ? f.id : Storage.ensureStock(f.name, f.boxIso)
        Storage.setStockFavourite(id, !f.favourite)
        app.reloadStocks()
        refreshFilms()
    }

    // Favourites first, then the five most recently loaded, then everything.
    // A search flattens it into one list of matches.
    readonly property var rows: {
        var list = page.films
        var q = page.query.toLowerCase()
        var out = []
        var i
        if (q.length > 0) {
            for (i = 0; i < list.length; i++)
                if (list[i].name.toLowerCase().indexOf(q) !== -1) out.push({ section: "", f: list[i] })
            return out
        }
        var favs = list.filter(function(f) { return f.favourite })
        var recent = list.filter(function(f) { return !f.favourite && f.lastUsed !== "" })
        recent.sort(function(a, b) { return a.lastUsed < b.lastUsed ? 1 : -1 })
        recent = recent.slice(0, 5)
        var shown = {}
        for (i = 0; i < favs.length; i++) { out.push({ section: i === 0 ? qsTr("favourites") : "", f: favs[i] }); shown[favs[i].name] = true }
        for (i = 0; i < recent.length; i++) { out.push({ section: i === 0 ? qsTr("recent") : "", f: recent[i] }); shown[recent[i].name] = true }
        var first = true
        for (i = 0; i < list.length; i++) {
            if (shown[list[i].name]) continue
            out.push({ section: first ? qsTr("all films") : "", f: list[i] })
            first = false
        }
        return out
    }

    function stopsLabel(iso) {
        if (!film || !(iso > 0)) return ""
        var stops = Math.log(iso / film.boxIso) / Math.LN2
        if (Math.abs(stops) < 0.17) return qsTr("box speed")
        var r = Math.abs(Math.round(stops * 3) / 3)
        var n = r % 1 === 0 ? r.toFixed(0) : r.toFixed(1)
        return stops > 0 ? qsTr("push %1").arg(n) : qsTr("pull %1").arg(n)
    }

    function loadFilm() {
        var stockId = film.id >= 0 ? film.id : Storage.ensureStock(film.name, film.boxIso)
        Storage.closeRollsForCamera(cameraId)
        var newId = Storage.addRoll(stockId, parseInt(isoField.text), cameraId, lensId,
                                    new Date().toISOString(), "")
        app.reloadStocks()
        app.reloadRolls()
        var meter = pageStack.find(function(p) { return typeof p.loadRoll === "function" })
        if (meter) {
            pageStack.pop(meter)
            meter.loadRoll(newId)
        } else {
            pageStack.pop()
        }
    }

    // A five-pointed star: filled for a favourite, outlined otherwise.
    Component {
        id: starMark
        Canvas {
            id: star
            property bool on: false
            property color fill: FiatLuxTheme.accent
            property color line: FiatLuxTheme.pillBorder
            width: Theme.iconSizeSmall
            height: width
            onOnChanged: requestPaint()
            onFillChanged: requestPaint()
            onLineChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var cx = width / 2, cy = height / 2 + height * 0.04
                var outer = width * 0.47, inner = outer * 0.42
                ctx.beginPath()
                for (var i = 0; i < 10; i++) {
                    var a = -Math.PI / 2 + i * Math.PI / 5
                    var rad = i % 2 === 0 ? outer : inner
                    var x = cx + rad * Math.cos(a), y = cy + rad * Math.sin(a)
                    if (i === 0) ctx.moveTo(x, y)
                    else ctx.lineTo(x, y)
                }
                ctx.closePath()
                if (star.on) {
                    ctx.fillStyle = star.fill
                    ctx.fill()
                }
                ctx.lineWidth = 2
                ctx.lineJoin = "round"
                ctx.strokeStyle = star.on ? star.fill : star.line
                ctx.stroke()
            }
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: page.width
            spacing: Theme.paddingLarge

            PageHead {
                title: qsTr("load film")
                subtitle: "fiat lux"
            }

            // ---- camera ----
            ComboBox {
                id: cameraCombo
                width: parent.width
                label: qsTr("into")
                enabled: app.cameraModel.count > 0
                description: app.cameraModel.count === 0
                             ? qsTr("No cameras yet. Add one from Cameras in the pull-down menu.") : ""
                menu: ContextMenu {
                    highlightColor: FiatLuxTheme.accent
                    Repeater {
                        model: app.cameraModel
                        MenuItem {
                            text: model.name
                            color: FiatLuxTheme.primaryText
                            onClicked: page.chooseCamera(app.cameraModel.get(index))
                        }
                    }
                }
            }

            // ---- film ----
            CardSection {
                title: qsTr("film")

                // Chosen: the film, and the way back to the list.
                Item {
                    visible: page.film !== null
                    width: parent.width
                    height: Math.max(chosenName.height, changeBtn.height)

                    Text {
                        id: chosenName
                        anchors.left: parent.left
                        anchors.right: changeBtn.left
                        anchors.rightMargin: Theme.paddingMedium
                        anchors.verticalCenter: parent.verticalCenter
                        wrapMode: Text.Wrap
                        text: page.film ? page.film.name + "  ·  ISO " + page.film.boxIso : ""
                        color: FiatLuxTheme.accent
                        font.pixelSize: Theme.fontSizeMedium
                        font.family: FiatLuxTheme.serif; font.italic: true
                    }

                    BackgroundItem {
                        id: changeBtn
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: changeText.implicitWidth + Theme.paddingLarge * 2
                        height: Theme.itemSizeExtraSmall
                        highlightedColor: FiatLuxTheme.highlightWash
                        onClicked: page.film = null
                        Rectangle {
                            anchors.fill: parent
                            radius: height / 2
                            color: FiatLuxTheme.pillFill
                            border.color: FiatLuxTheme.pillBorder
                            border.width: 1
                        }
                        Text {
                            id: changeText
                            anchors.centerIn: parent
                            text: qsTr("change")
                            color: FiatLuxTheme.primaryText
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                }

                // Not chosen yet: search and the list.
                Column {
                    visible: page.film === null
                    width: parent.width
                    spacing: 0

                    SearchField {
                        id: searchField
                        width: parent.width + Theme.paddingLarge * 2
                        x: -Theme.paddingLarge
                        placeholderText: qsTr("search films")
                        color: FiatLuxTheme.primaryText
                        onTextChanged: page.query = text
                    }

                    Repeater {
                        model: page.film === null ? page.rows : []
                        delegate: Column {
                            width: parent.width

                            Text {
                                visible: modelData.section !== ""
                                height: visible ? implicitHeight + Theme.paddingMedium : 0
                                verticalAlignment: Text.AlignBottom
                                text: modelData.section
                                color: FiatLuxTheme.secondaryText
                                font.pixelSize: Theme.fontSizeExtraSmall
                                font.family: FiatLuxTheme.serif; font.italic: true
                            }

                            BackgroundItem {
                                id: filmRow
                                width: parent.width
                                height: Theme.itemSizeSmall
                                highlightedColor: FiatLuxTheme.highlightWash
                                onClicked: page.chooseFilm(modelData.f)

                                Text {
                                    anchors.left: parent.left
                                    anchors.right: isoText.left
                                    anchors.rightMargin: Theme.paddingMedium
                                    anchors.verticalCenter: parent.verticalCenter
                                    elide: Text.ElideRight
                                    text: modelData.f.name
                                    color: FiatLuxTheme.primaryText
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                                Text {
                                    id: isoText
                                    anchors.right: favBtn.left
                                    anchors.rightMargin: Theme.paddingMedium
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.f.boxIso
                                    color: FiatLuxTheme.secondaryText
                                    font.pixelSize: Theme.fontSizeExtraSmall
                                }

                                MouseArea {
                                    id: favBtn
                                    anchors.right: parent.right
                                    width: Theme.itemSizeExtraSmall
                                    height: parent.height
                                    onClicked: page.toggleFavourite(modelData.f)
                                    Loader {
                                        anchors.centerIn: parent
                                        sourceComponent: starMark
                                        onLoaded: item.on = Qt.binding(function() { return modelData.f.favourite })
                                    }
                                }
                            }
                        }
                    }

                    BackgroundItem {
                        width: parent.width
                        height: Theme.itemSizeSmall
                        highlightedColor: FiatLuxTheme.highlightWash
                        onClicked: pageStack.push(Qt.resolvedUrl("AddStockPage.qml"))
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("+ add a film that isn't listed")
                            color: FiatLuxTheme.accent
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: FiatLuxTheme.serif; font.italic: true
                        }
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: qsTr("Tap the star to keep a film among your favourites.")
                        color: FiatLuxTheme.secondaryText
                        font.pixelSize: Theme.fontSizeExtraSmall
                    }
                }
            }

            // ---- speed ----
            CardSection {
                visible: page.film !== null
                title: qsTr("shoot at")
                Row {
                    width: parent.width
                    spacing: Theme.paddingMedium
                    TextField {
                        id: isoField
                        width: Theme.itemSizeHuge
                        label: qsTr("ISO")
                        color: FiatLuxTheme.primaryText
                        inputMethodHints: Qt.ImhDigitsOnly
                        maximumLength: 5
                        validator: IntValidator { bottom: 1; top: 99999 }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: page.stopsLabel(parseInt(isoField.text))
                        color: FiatLuxTheme.secondaryText
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: FiatLuxTheme.serif; font.italic: true
                    }
                }
                Flow {
                    width: parent.width
                    spacing: Theme.paddingSmall
                    Repeater {
                        model: [ { l: qsTr("pull 1"), k: 0.5 }, { l: qsTr("box"), k: 1 },
                                 { l: qsTr("push 1"), k: 2 }, { l: qsTr("push 2"), k: 4 } ]
                        delegate: BackgroundItem {
                            id: speedPill
                            width: spText.implicitWidth + Theme.paddingLarge * 2
                            height: spText.implicitHeight + Theme.paddingMedium * 1.5
                            highlightedColor: "transparent"
                            readonly property bool on: page.film !== null
                                                       && parseInt(isoField.text) === Math.round(page.film.boxIso * modelData.k)
                            onClicked: if (page.film) isoField.text = Math.round(page.film.boxIso * modelData.k).toString()
                            Rectangle {
                                anchors.fill: parent
                                radius: height / 2
                                color: speedPill.on || speedPill.highlighted ? FiatLuxTheme.pillFillActive : FiatLuxTheme.pillFill
                                border.color: speedPill.on ? FiatLuxTheme.pillBorderActive : FiatLuxTheme.pillBorder
                                border.width: 1
                            }
                            Text {
                                id: spText
                                anchors.centerIn: parent
                                text: modelData.l
                                color: speedPill.on ? FiatLuxTheme.accent : FiatLuxTheme.primaryText
                                font.pixelSize: Theme.fontSizeSmall
                            }
                        }
                    }
                }
            }

            // ---- lens (interchangeable only) ----
            ComboBox {
                id: lensCombo
                visible: page.cameraId >= 0 && page.cameraType !== 0
                width: parent.width
                label: qsTr("lens")
                enabled: page.compatLenses.length > 0
                description: page.compatLenses.length === 0
                             ? qsTr("No lenses with the mount “%1” yet. You can load the film now and add lenses later.").arg(page.cameraMount)
                             : ""
                menu: ContextMenu {
                    highlightColor: FiatLuxTheme.accent
                    Repeater {
                        model: page.compatLenses
                        MenuItem {
                            text: modelData.name
                            color: FiatLuxTheme.primaryText
                            onClicked: page.lensId = modelData.id
                        }
                    }
                }
            }

            BackgroundItem {
                id: loadBtn
                width: parent.width; height: Theme.itemSizeLarge
                enabled: page.canLoad
                opacity: enabled ? 1.0 : 0.35
                onClicked: page.loadFilm()
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    height: Theme.itemSizeMedium; radius: Theme.paddingLarge
                    color: loadBtn.highlighted ? FiatLuxTheme.amberStrong : FiatLuxTheme.amber
                    Text {
                        anchors.centerIn: parent
                        text: qsTr("load film")
                        color: FiatLuxTheme.onAccent
                        font.pixelSize: Theme.fontSizeMedium
                        font.family: FiatLuxTheme.serif; font.italic: true; font.bold: true
                    }
                }
            }

            Item { width: 1; height: Theme.paddingLarge }
        }

        VerticalScrollDecorator { }
    }
}
