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
// button come up under it instead of below fifty other films. "change" brings
// the list back.

Page {
    id: page
    allowedOrientations: Orientation.Portrait

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

    readonly property var speedChoices: [
        { label: qsTr("pull 1"), value: 0.5 }, { label: qsTr("box"), value: 1 },
        { label: qsTr("push 1"), value: 2 }, { label: qsTr("push 2"), value: 4 } ]

    readonly property var currentFactor: {
        if (!page.film) return null
        var iso = parseInt(isoField.text)
        for (var i = 0; i < page.speedChoices.length; i++) {
            var k = page.speedChoices[i].value
            if (iso === Math.round(page.film.boxIso * k)) return k
        }
        return null
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
            property color line: FiatLuxTheme.secondaryText
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

    PaperBackground { }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: page.width

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
                value: currentIndex < 0 ? (app.cameraModel.count > 0 ? qsTr("choose") : qsTr("no cameras")) : (currentItem ? currentItem.text : "")
                description: app.cameraModel.count === 0
                             ? qsTr("Add a camera first, from Cameras in the pull-down menu.") : ""
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

            // ---- lens (interchangeable only) ----
            ComboBox {
                id: lensCombo
                visible: page.cameraId >= 0 && page.cameraType !== 0
                width: parent.width
                label: qsTr("lens")
                enabled: page.compatLenses.length > 0
                value: currentIndex < 0 ? (page.compatLenses.length > 0 ? qsTr("choose") : qsTr("none yet")) : (currentItem ? currentItem.text : "")
                description: page.compatLenses.length === 0
                             ? qsTr("No lenses with the mount \u201c%1\u201d yet. Load the film now and add lenses later.").arg(page.cameraMount)
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

            // ---- film ----
            SectionTitle {
                text: qsTr("film")
            }

            // Chosen: the film, and the way back to the list.
            Item {
                visible: page.film !== null
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                height: Math.max(chosenName.height, changeLink.height)

                Label {
                    id: chosenName
                    anchors.left: parent.left
                    anchors.right: changeLink.left
                    anchors.rightMargin: Theme.paddingMedium
                    anchors.verticalCenter: parent.verticalCenter
                    wrapMode: Text.Wrap
                    text: page.film ? page.film.name + "  \u00b7  ISO " + page.film.boxIso : ""
                    color: FiatLuxTheme.accent
                    font.pixelSize: Theme.fontSizeMedium
                    font.family: FiatLuxTheme.serif
                    font.italic: true
                }

                LinkText {
                    id: changeLink
                    anchors.right: parent.right
                    anchors.rightMargin: -Theme.paddingSmall
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("change")
                    onClicked: page.film = null
                }
            }

            // Not chosen yet: search and the list.
            Column {
                visible: page.film === null
                width: parent.width

                SearchField {
                    id: searchField
                    width: parent.width
                    placeholderText: qsTr("search films")
                    color: FiatLuxTheme.primaryText
                    onTextChanged: page.query = text
                }

                Repeater {
                    model: page.film === null ? page.rows : []
                    delegate: Column {
                        width: parent.width

                        SectionTitle {
                            visible: modelData.section !== ""
                            text: modelData.section
                            font.pixelSize: Theme.fontSizeExtraSmall
                        }

                        BackgroundItem {
                            id: filmRow
                            width: parent.width
                            height: Theme.itemSizeSmall
                            highlightedColor: FiatLuxTheme.highlightWash
                            onClicked: page.chooseFilm(modelData.f)

                            Label {
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.horizontalPageMargin
                                anchors.right: isoText.left
                                anchors.rightMargin: Theme.paddingMedium
                                anchors.verticalCenter: parent.verticalCenter
                                truncationMode: TruncationMode.Fade
                                text: modelData.f.name
                                color: FiatLuxTheme.primaryText
                                font.pixelSize: Theme.fontSizeSmall
                            }
                            Label {
                                id: isoText
                                anchors.right: favBtn.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.f.boxIso
                                color: FiatLuxTheme.secondaryText
                                font.pixelSize: Theme.fontSizeExtraSmall
                            }

                            MouseArea {
                                id: favBtn
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.horizontalPageMargin - Theme.paddingMedium
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

                LinkText {
                    x: Theme.horizontalPageMargin - Theme.paddingSmall
                    text: qsTr("+ a film that isn\u2019t listed")
                    underline: false
                    italic: true
                    onClicked: pageStack.push(Qt.resolvedUrl("AddStockPage.qml"))
                }

                FormNote {
                    text: qsTr("Tap the star to keep a film among your favourites.")
                }
            }

            // ---- speed ----
            SectionTitle {
                visible: page.film !== null
                text: qsTr("shoot at")
            }

            Row {
                visible: page.film !== null
                width: parent.width
                TextField {
                    id: isoField
                    width: Theme.itemSizeHuge * 1.4
                    label: qsTr("ISO")
                    color: FiatLuxTheme.primaryText
                    inputMethodHints: Qt.ImhDigitsOnly
                    maximumLength: 5
                    validator: IntValidator { bottom: 1; top: 99999 }
                    EnterKey.iconSource: "image://theme/icon-m-enter-close"
                    EnterKey.onClicked: focus = false
                }
                Label {
                    anchors.top: parent.top
                    anchors.topMargin: Theme.paddingSmall
                    text: page.stopsLabel(parseInt(isoField.text))
                    color: FiatLuxTheme.secondaryText
                    font.pixelSize: Theme.fontSizeMedium
                    font.family: FiatLuxTheme.serif
                    font.italic: true
                }
            }

            WordChoice {
                visible: page.film !== null
                x: Theme.horizontalPageMargin - Theme.paddingSmall
                width: parent.width - Theme.horizontalPageMargin * 2
                choices: page.speedChoices
                current: page.currentFactor
                onChosen: if (page.film) isoField.text = Math.round(page.film.boxIso * value).toString()
            }

            Item { width: 1; height: Theme.paddingLarge * 2 }

            FiatButton {
                text: qsTr("load film")
                enabled: page.canLoad
                onClicked: page.loadFilm()
            }

            Item { width: 1; height: Theme.paddingLarge }
        }

        VerticalScrollDecorator { }
    }
}
