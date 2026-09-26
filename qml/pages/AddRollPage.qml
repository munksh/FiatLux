import QtQuick 2.0
import Sailfish.Silica 1.0
import "../Storage.js" as Storage
import "../FilmCatalogue.js" as Catalogue
import ".." 1.0

// Load film: which camera, which film, and the speed you shoot it at. Loading
// a film into a camera closes whatever roll was in it before; that roll and
// its shots stay in the log.

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

    // Accepted from older call sites; the page always returns to the meter.
    property bool returnToMeter: true
    property int presetCameraId: -1

    property int cameraId: -1
    property int cameraType: -1
    property string cameraLabel: qsTr("tap to choose")
    property string cameraMount: ""
    property var compatLenses: []
    property int lensId: -1
    property string lensLabel: qsTr("tap to choose")

    property var films: []
    property var film: null      // { id, name, boxIso }
    property string query: ""

    readonly property bool canLoad: film !== null && cameraId >= 0 && parseInt(isoField.text) > 0

    Component.onCompleted: {
        refreshFilms()
        if (presetCameraId >= 0) chooseCamera(Storage.getCamera(presetCameraId))
        else if (app.cameraModel.count === 1) chooseCamera(app.cameraModel.get(0))
    }

    // Back from "add a film that isn't listed": pick up what was added.
    onStatusChanged: if (status === PageStatus.Active) refreshFilms()

    function refreshFilms() {
        films = Storage.filmsForPicker(Catalogue.films)
    }

    function chooseCamera(c) {
        if (!c) return
        cameraId = c.id
        cameraType = c.type
        cameraLabel = c.name
        cameraMount = c.mount || ""
        compatLenses = cameraType !== 0 && cameraMount.length > 0 ? Storage.lensesForMount(cameraMount) : []
        lensId = compatLenses.length === 1 ? compatLenses[0].id : -1
        lensLabel = compatLenses.length === 1 ? compatLenses[0].name : qsTr("tap to choose")
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
        if (film && film.name === f.name) film = { id: id, name: f.name, boxIso: f.boxIso }
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

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: page.width
            spacing: Theme.paddingLarge

            Item {
                width: parent.width; height: Theme.itemSizeLarge
                Text {
                    anchors.centerIn: parent
                    text: qsTr("load film")
                    color: FiatLuxTheme.primaryText
                    font.pixelSize: Theme.fontSizeLarge
                    font.family: FiatLuxTheme.serif; font.italic: true
                }
            }

            // ---- camera ----
            CardSection {
                title: qsTr("into")
                ChooserRow {
                    label: page.cameraLabel
                    onTapped: {
                        var arr = []
                        for (var i = 0; i < app.cameraModel.count; i++)
                            arr.push(app.cameraModel.get(i).name)
                        cameraMenu.items = arr
                        cameraMenu.show(anchor)
                    }
                }
                Text {
                    visible: app.cameraModel.count === 0
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: qsTr("No cameras yet. Add one from Cameras in the pull-down menu.")
                    color: FiatLuxTheme.secondaryText
                    font.pixelSize: Theme.fontSizeExtraSmall
                }
            }

            // ---- film ----
            CardSection {
                title: qsTr("film")

                Text {
                    visible: page.film !== null
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: page.film ? page.film.name + "  ·  ISO " + page.film.boxIso : ""
                    color: FiatLuxTheme.accent
                    font.pixelSize: Theme.fontSizeMedium
                    font.family: FiatLuxTheme.serif; font.italic: true
                }

                SearchField {
                    id: searchField
                    width: parent.width + Theme.paddingLarge * 2
                    x: -Theme.paddingLarge
                    placeholderText: page.film ? qsTr("change film") : qsTr("search films")
                    color: FiatLuxTheme.primaryText
                    onTextChanged: page.query = text
                }

                Column {
                    width: parent.width
                    spacing: 0

                    Repeater {
                        model: page.rows
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
                                readonly property bool chosen: page.film !== null && page.film.name === modelData.f.name
                                onClicked: page.chooseFilm(modelData.f)

                                Text {
                                    anchors.left: parent.left
                                    anchors.right: isoText.left
                                    anchors.rightMargin: Theme.paddingMedium
                                    anchors.verticalCenter: parent.verticalCenter
                                    elide: Text.ElideRight
                                    text: modelData.f.name
                                    color: filmRow.chosen ? FiatLuxTheme.accent : FiatLuxTheme.primaryText
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

                                // Favourite: a filled mark, or an empty ring.
                                MouseArea {
                                    id: favBtn
                                    anchors.right: parent.right
                                    width: Theme.itemSizeExtraSmall
                                    height: parent.height
                                    onClicked: page.toggleFavourite(modelData.f)
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: Theme.paddingLarge
                                        height: width
                                        radius: width / 2
                                        color: modelData.f.favourite ? FiatLuxTheme.accent : "transparent"
                                        border.color: modelData.f.favourite ? FiatLuxTheme.accent : FiatLuxTheme.pillBorder
                                        border.width: 2
                                    }
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
                    text: qsTr("Tap the ring to keep a film among your favourites.")
                    color: FiatLuxTheme.secondaryText
                    font.pixelSize: Theme.fontSizeExtraSmall
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
            CardSection {
                visible: page.cameraId >= 0 && page.cameraType !== 0
                title: qsTr("lens")
                ChooserRow {
                    label: page.lensLabel
                    enabled: page.compatLenses.length > 0
                    onTapped: {
                        var arr = []
                        for (var i = 0; i < page.compatLenses.length; i++)
                            arr.push(page.compatLenses[i].name)
                        lensMenu.items = arr
                        lensMenu.show(anchor)
                    }
                }
                Text {
                    visible: page.compatLenses.length === 0
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: qsTr("No lenses with the mount “%1” yet. You can load the film now and add lenses later.").arg(page.cameraMount)
                    color: FiatLuxTheme.secondaryText
                    font.pixelSize: Theme.fontSizeExtraSmall
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
    }

    PillMenu {
        id: cameraMenu
        onPicked: function(idx) { page.chooseCamera(app.cameraModel.get(idx)) }
    }

    PillMenu {
        id: lensMenu
        onPicked: function(idx) {
            page.lensId = page.compatLenses[idx].id
            page.lensLabel = page.compatLenses[idx].name
        }
    }
}
