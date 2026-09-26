import QtQuick 2.0
import Sailfish.Silica 1.0
import "../Storage.js" as Storage
import ".." 1.0
import "../components"

// Everything you have photographed, over a month, a quarter or a year: how
// many frames, on how many days, on how many rolls; a bar chart of when; which
// cameras and films did the work; and the rolls themselves, each opening its
// own page with every frame.

Page {
    id: page
    allowedOrientations: Orientation.Portrait

    property int lookback: 365

    // NOT `data`: that is Item's default property (see Fiat Mos, History).
    property var bars: []          // [{ start: Date, count: n }], oldest first
    property bool weekly: true
    property int frames: 0
    property int shootingDays: 0
    property int rollCount: 0
    property int busiest: 0
    property var byCamera: []      // [{ name, count }], most first
    property var byFilm: []
    property var rolls: []         // [{ id, stockName, cameraName, frames, first, last, open }]

    function paint() { FiatLuxTheme.applyPalette(page) }
    Connections {
        target: FiatLuxTheme
        onAmbientChanged: page.paint()
    }

    function localDay(d) { return new Date(d.getFullYear(), d.getMonth(), d.getDate()) }
    function dayKey(d) { return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate() }

    // Monday of the week a day falls in.
    function weekStart(d) {
        var wd = (d.getDay() + 6) % 7
        return new Date(d.getFullYear(), d.getMonth(), d.getDate() - wd)
    }

    function tally(map, key) {
        map[key] = (map[key] || 0) + 1
    }

    function ranked(map, limit) {
        var out = []
        for (var k in map) out.push({ name: k, count: map[k] })
        out.sort(function(a, b) { return b.count - a.count })
        return out.slice(0, limit)
    }

    function refresh() {
        var today = localDay(new Date())
        var start = new Date(today.getFullYear(), today.getMonth(), today.getDate() - (lookback - 1))
        var shots = Storage.shotsSince(start.toISOString())

        weekly = lookback > 90
        var first = weekly ? weekStart(start) : start
        var bucketDays = weekly ? 7 : 1
        var n = Math.floor((today - first) / 86400000 / bucketDays) + 1
        var counts = []
        for (var b = 0; b < n; b++) counts.push(0)

        var days = {}
        var cams = {}, films = {}, rollMap = {}
        for (var i = 0; i < shots.length; i++) {
            var s = shots[i]
            var t = new Date(s.timestamp)
            if (isNaN(t.getTime())) continue
            var d = localDay(t)
            if (d < start) continue
            var idx = Math.floor((d - first) / 86400000 / bucketDays)
            if (idx >= 0 && idx < n) counts[idx]++
            days[dayKey(d)] = true
            tally(cams, s.cameraName !== "" ? s.cameraName : qsTr("Quick Meter"))
            tally(films, s.stockName !== "" ? s.stockName : qsTr("no film"))
            if (!rollMap[s.rollId]) {
                rollMap[s.rollId] = { id: s.rollId, stockName: s.stockName, cameraName: s.cameraName,
                                      frames: 0, first: d, last: d, open: !s.closed }
            }
            var r = rollMap[s.rollId]
            r.frames++
            if (d < r.first) r.first = d
            if (d > r.last) r.last = d
        }

        var out = [], most = 0
        for (var j = 0; j < n; j++) {
            out.push({ start: new Date(first.getFullYear(), first.getMonth(), first.getDate() + j * bucketDays),
                       count: counts[j] })
            if (counts[j] > most) most = counts[j]
        }

        var rl = []
        for (var id in rollMap) rl.push(rollMap[id])
        rl.sort(function(a, b) { return b.last - a.last })

        var nDays = 0
        for (var k in days) nDays++

        bars = out
        busiest = most
        frames = shots.length
        shootingDays = nDays
        rollCount = rl.length
        byCamera = ranked(cams, 5)
        byFilm = ranked(films, 5)
        rolls = rl
        chart.requestPaint()
    }

    onLookbackChanged: refresh()
    Component.onCompleted: {
        paint()
        refresh()
    }
    onStatusChanged: if (status === PageStatus.Active) refresh()

    function perDay() {
        if (page.shootingDays === 0) return "–"
        var v = page.frames / page.shootingDays
        return v % 1 === 0 ? v.toFixed(0) : v.toFixed(1)
    }

    function span(r) {
        var a = Qt.formatDate(r.first, "d MMM")
        var b = Qt.formatDate(r.last, "d MMM")
        return a === b ? a : a + " – " + b
    }

    PaperBackground { }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: body.height + Theme.paddingLarge

        Column {
            id: body
            width: parent.width
            spacing: Theme.paddingMedium

            PageHead {
                title: qsTr("history")
                subtitle: "fiat lux"
            }

            WordChoice {
                x: Theme.horizontalPageMargin - Theme.paddingSmall
                width: parent.width - Theme.horizontalPageMargin * 2
                choices: [ { label: qsTr("30 days"), value: 30 },
                           { label: qsTr("90 days"), value: 90 },
                           { label: qsTr("a year"), value: 365 } ]
                current: page.lookback
                onChosen: page.lookback = value
            }

            // ---- four numbers ----
            Row {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2

                Repeater {
                    model: [
                        { n: "" + page.frames, what: page.frames === 1 ? qsTr("frame") : qsTr("frames"), accent: true },
                        { n: "" + page.rollCount, what: page.rollCount === 1 ? qsTr("roll") : qsTr("rolls"), accent: false },
                        { n: "" + page.shootingDays, what: page.shootingDays === 1 ? qsTr("day") : qsTr("days"), accent: false },
                        { n: page.perDay(), what: qsTr("per day"), accent: false }
                    ]
                    Column {
                        width: parent.width / 4
                        Label {
                            text: modelData.n
                            font.pixelSize: Theme.fontSizeExtraLarge
                            font.family: FiatLuxTheme.serif
                            color: modelData.accent ? FiatLuxTheme.accent : FiatLuxTheme.primaryText
                        }
                        SectionLabel {
                            width: parent.width
                            truncationMode: TruncationMode.Fade
                            text: modelData.what
                        }
                    }
                }
            }

            FormNote {
                text: qsTr("Days are the days you shot on, and per day is frames on those days.")
            }

            // ---- when ----
            SectionTitle {
                text: page.weekly ? qsTr("frames per week") : qsTr("frames per day")
            }

            Column {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                spacing: Theme.paddingSmall

                Item {
                    width: parent.width
                    height: Theme.itemSizeExtraLarge * 1.4

                    Label {
                        id: maxLabel
                        anchors.left: parent.left
                        anchors.top: parent.top
                        font.pixelSize: Theme.fontSizeTiny
                        color: FiatLuxTheme.secondaryText
                        text: "" + Math.max(1, page.busiest)
                    }
                    Label {
                        id: zeroLabel
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        font.pixelSize: Theme.fontSizeTiny
                        color: FiatLuxTheme.secondaryText
                        text: "0"
                    }

                    Canvas {
                        id: chart
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: parent.width - Math.max(maxLabel.width, zeroLabel.width) - Theme.paddingMedium
                        renderStrategy: Canvas.Immediate

                        property color bar: FiatLuxTheme.accent
                        property color base: FiatLuxTheme.innerBorder
                        onBarChanged: requestPaint()
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()

                        // A Canvas loses its texture while the app is in the
                        // background, as Fiat Mos found out.
                        Connections {
                            target: Qt.application
                            onStateChanged: if (Qt.application.state === Qt.ApplicationActive) chart.requestPaint()
                        }

                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()
                            ctx.clearRect(0, 0, width, height)
                            var d = page.bars
                            if (!d || d.length === 0) return
                            var maxV = Math.max(1, page.busiest)

                            ctx.strokeStyle = base
                            ctx.lineWidth = 1
                            ctx.beginPath()
                            ctx.moveTo(0, height - 0.5)
                            ctx.lineTo(width, height - 0.5)
                            ctx.stroke()

                            var bw = width / d.length
                            var gap = bw > 4 ? Math.max(1, bw * 0.15) : 0
                            ctx.fillStyle = bar
                            for (var j = 0; j < d.length; j++) {
                                if (d[j].count === 0) continue
                                var h = Math.max(2, (d[j].count / maxV) * height)
                                ctx.fillRect(j * bw, height - h, Math.max(1, bw - gap), h)
                            }
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: firstLabel.height
                    Label {
                        id: firstLabel
                        x: parent.width - chart.width
                        font.pixelSize: Theme.fontSizeTiny
                        color: FiatLuxTheme.secondaryText
                        text: page.bars.length > 0 ? Qt.formatDate(page.bars[0].start, "d MMM yyyy") : ""
                    }
                    Label {
                        anchors.right: parent.right
                        font.pixelSize: Theme.fontSizeTiny
                        color: FiatLuxTheme.secondaryText
                        text: qsTr("today")
                    }
                }
            }

            // ---- what did the work ----
            Repeater {
                model: [ { title: qsTr("cameras"), list: page.byCamera },
                         { title: qsTr("films"), list: page.byFilm } ]
                delegate: Column {
                    width: body.width
                    visible: modelData.list.length > 0
                    readonly property var list: modelData.list
                    readonly property int most: list.length > 0 ? list[0].count : 1

                    SectionTitle {
                        text: modelData.title
                    }

                    Repeater {
                        model: parent.list
                        delegate: Item {
                            x: Theme.horizontalPageMargin
                            width: body.width - Theme.horizontalPageMargin * 2
                            height: nameLabel.height + Theme.paddingSmall * 3

                            Label {
                                id: nameLabel
                                anchors.left: parent.left
                                anchors.right: countLabel.left
                                anchors.rightMargin: Theme.paddingMedium
                                truncationMode: TruncationMode.Fade
                                text: modelData.name
                                color: FiatLuxTheme.primaryText
                                font.pixelSize: Theme.fontSizeSmall
                            }
                            Label {
                                id: countLabel
                                anchors.right: parent.right
                                text: modelData.count
                                color: FiatLuxTheme.secondaryText
                                font.pixelSize: Theme.fontSizeSmall
                            }
                            // How much, as a thin bar under the name.
                            Rectangle {
                                anchors.top: nameLabel.bottom
                                anchors.topMargin: Theme.paddingSmall / 2
                                width: parent.width * modelData.count / Math.max(1, parent.parent.most)
                                height: Math.max(2, Theme.paddingSmall / 2)
                                color: FiatLuxTheme.accent
                                opacity: 0.7
                            }
                        }
                    }
                }
            }

            // ---- the rolls ----
            SectionTitle {
                text: qsTr("rolls")
            }

            FormNote {
                visible: page.rolls.length === 0
                text: qsTr("Nothing logged in this time. Log shot on the meter adds frames to the film in the camera.")
            }

            Repeater {
                model: page.rolls
                delegate: BackgroundItem {
                    width: body.width
                    height: rollCol.height + Theme.paddingMedium * 2
                    highlightedColor: FiatLuxTheme.highlightWash
                    onClicked: pageStack.push(Qt.resolvedUrl("ShotsPage.qml"), { rollId: modelData.id })

                    Rectangle {
                        anchors.bottom: parent.bottom
                        x: Theme.horizontalPageMargin
                        width: parent.width - Theme.horizontalPageMargin * 2
                        height: 1
                        color: FiatLuxTheme.innerBorder
                        visible: index < page.rolls.length - 1
                    }

                    Column {
                        id: rollCol
                        x: Theme.horizontalPageMargin
                        width: parent.width - Theme.horizontalPageMargin * 2
                        anchors.verticalCenter: parent.verticalCenter
                        Label {
                            width: parent.width
                            truncationMode: TruncationMode.Fade
                            text: modelData.stockName !== "" ? modelData.stockName : qsTr("no film")
                            color: FiatLuxTheme.primaryText
                            font.pixelSize: Theme.fontSizeMedium
                            font.family: FiatLuxTheme.serif
                            font.italic: true
                        }
                        Label {
                            width: parent.width
                            truncationMode: TruncationMode.Fade
                            text: [modelData.cameraName,
                                   modelData.frames === 1 ? qsTr("1 frame") : qsTr("%1 frames").arg(modelData.frames),
                                   page.span(modelData)].concat(modelData.open ? [qsTr("loaded")] : []).join("  ·  ")
                            color: FiatLuxTheme.secondaryText
                            font.pixelSize: Theme.fontSizeExtraSmall
                        }
                    }
                }
            }

            Item { width: 1; height: Theme.paddingLarge }
        }

        VerticalScrollDecorator { }
    }
}
