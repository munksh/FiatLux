import QtQuick 2.0
import Sailfish.Silica 1.0
import "../Storage.js" as Storage
import ".." 1.0
import "../components"

// One roll: how many frames, on how many days, and a bar per day from the day
// it was loaded until today -- the same chart as History in Fiat Mos. Then
// every frame, with its pair and its picture.

Page {
    id: page
    allowedOrientations: Orientation.Portrait

    property int rollId: -1
    property var roll: null

    // NOT `data`: that is Item's default property (see Fiat Mos, History).
    property var days: []          // [{ day: Date, count: n }], oldest first
    property int frames: 0
    property int shootingDays: 0
    property int busiest: 0

    ListModel { id: shotModel }

    function paint() { FiatLuxTheme.applyPalette(page) }
    Connections {
        target: FiatLuxTheme
        onAmbientChanged: page.paint()
    }

    function localDay(d) { return new Date(d.getFullYear(), d.getMonth(), d.getDate()) }
    function dayKey(d) { return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate() }

    function refresh() {
        roll = Storage.getRoll(rollId)
        Storage.loadShots(shotModel, rollId)

        var counts = {}
        var first = null, last = null
        for (var i = 0; i < shotModel.count; i++) {
            var t = new Date(shotModel.get(i).timestamp)
            if (isNaN(t.getTime())) continue
            var d = localDay(t)
            counts[dayKey(d)] = (counts[dayKey(d)] || 0) + 1
            if (first === null || d < first) first = d
            if (last === null || d > last) last = d
        }

        // From the day the film went in (or the first frame, if earlier) to
        // today. At most a year of bars; a roll that has been in longer than
        // that shows its last year.
        var start = roll ? localDay(new Date(roll.startDate)) : first
        if (start === null || isNaN(start.getTime())) start = first !== null ? first : localDay(new Date())
        if (first !== null && first < start) start = first
        var end = localDay(new Date())
        if (last !== null && last > end) end = last
        var n = Math.round((end - start) / 86400000) + 1
        if (n > 365) {
            start = new Date(end.getFullYear(), end.getMonth(), end.getDate() - 364)
            n = 365
        }

        var out = []
        var shooting = 0, most = 0
        for (var k = 0; k < n; k++) {
            var day = new Date(start.getFullYear(), start.getMonth(), start.getDate() + k)
            var c = counts[dayKey(day)] || 0
            if (c > 0) shooting++
            if (c > most) most = c
            out.push({ day: day, count: c })
        }
        days = out
        frames = shotModel.count
        shootingDays = shooting
        busiest = most
        chart.requestPaint()
    }

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

    function when(iso) {
        var d = new Date(iso)
        if (isNaN(d.getTime())) return ""
        return Qt.formatTime(d, "hh:mm") + ", " + Qt.formatDate(d, "d MMM")
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
                title: page.roll ? page.roll.stockName : qsTr("roll")
                subtitle: page.roll ? page.roll.cameraName : ""
            }

            // ---- three numbers ----
            Row {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2

                Repeater {
                    model: [
                        { n: "" + page.frames, what: page.frames === 1 ? qsTr("frame") : qsTr("frames"), accent: true },
                        { n: "" + page.shootingDays, what: page.shootingDays === 1 ? qsTr("day") : qsTr("days"), accent: false },
                        { n: page.perDay(), what: qsTr("per day"), accent: false }
                    ]
                    Column {
                        width: parent.width / 3
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

            // ---- frames per day ----
            //
            // Bars, time left to right: the day the film went in at the left,
            // today at the right. A day without a frame is simply no bar.
            SectionTitle {
                text: qsTr("frames per day")
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
                            var d = page.days
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

                // Both ends dated: an unlabelled axis is decoration.
                Item {
                    width: parent.width
                    height: firstDay.height
                    Label {
                        id: firstDay
                        x: parent.width - chart.width
                        font.pixelSize: Theme.fontSizeTiny
                        color: FiatLuxTheme.secondaryText
                        text: page.days.length > 0 ? Qt.formatDate(page.days[0].day, "d MMM") : ""
                    }
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        font.pixelSize: Theme.fontSizeTiny
                        color: FiatLuxTheme.secondaryText
                        text: page.days.length === 1 ? qsTr("1 day") : qsTr("%1 days").arg(page.days.length)
                    }
                    Label {
                        anchors.right: parent.right
                        font.pixelSize: Theme.fontSizeTiny
                        color: FiatLuxTheme.secondaryText
                        text: qsTr("today")
                    }
                }
            }

            // ---- every frame ----
            SectionTitle {
                text: qsTr("frames")
            }

            FormNote {
                visible: page.frames === 0
                text: qsTr("No frames yet. Log shot on the meter adds one, with its picture.")
            }

            Repeater {
                model: shotModel
                delegate: ListItem {
                    id: shot
                    width: body.width
                    contentHeight: Theme.itemSizeLarge
                    highlightedColor: FiatLuxTheme.highlightWash
                    readonly property int shotId: model.id
                    readonly property string photo: model.photoPath
                    onClicked: openMenu()

                    Rectangle {
                        anchors.bottom: parent.bottom
                        x: Theme.horizontalPageMargin
                        width: parent.width - Theme.horizontalPageMargin * 2
                        height: 1
                        color: FiatLuxTheme.innerBorder
                        visible: index < shotModel.count - 1
                    }

                    Label {
                        id: frameNo
                        x: Theme.horizontalPageMargin
                        width: Theme.itemSizeExtraSmall
                        anchors.verticalCenter: parent.verticalCenter
                        text: model.frame
                        color: FiatLuxTheme.accent
                        font.pixelSize: Theme.fontSizeLarge
                        font.family: FiatLuxTheme.serif
                    }

                    Rectangle {
                        id: thumbFrame
                        anchors.left: frameNo.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.itemSizeMedium * 0.8
                        height: width
                        // Kept even without a picture, so every row's text
                        // starts at the same place.
                        color: shot.photo !== "" ? FiatLuxTheme.viewfinderBg : "transparent"
                        Image {
                            visible: shot.photo !== ""
                            anchors.fill: parent
                            source: shot.photo !== "" ? "file://" + shot.photo : ""
                            sourceSize.width: width
                            sourceSize.height: height
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            clip: true
                        }
                    }

                    Column {
                        anchors.left: thumbFrame.right
                        anchors.leftMargin: Theme.paddingLarge
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        Label {
                            width: parent.width
                            truncationMode: TruncationMode.Fade
                            text: "f/" + model.aperture + "   " + model.shutterSpeed + "   ISO " + model.iso
                            color: FiatLuxTheme.primaryText
                            font.pixelSize: Theme.fontSizeMedium
                        }
                        Label {
                            width: parent.width
                            truncationMode: TruncationMode.Fade
                            text: "EV " + (model.ev !== undefined && model.ev !== null ? Number(model.ev).toFixed(1) : "–")
                                  + "  ·  " + page.when(model.timestamp)
                            color: FiatLuxTheme.secondaryText
                            font.pixelSize: Theme.fontSizeExtraSmall
                        }
                    }

                    menu: ContextMenu {
                        highlightColor: FiatLuxTheme.accent
                        MenuItem {
                            visible: shot.photo !== ""
                            text: qsTr("Open the picture")
                            color: FiatLuxTheme.primaryText
                            onClicked: Qt.openUrlExternally("file://" + shot.photo)
                        }
                        MenuItem {
                            text: qsTr("Delete this frame")
                            color: FiatLuxTheme.primaryText
                            onClicked: {
                                var id = shot.shotId
                                shot.remorseAction(qsTr("Deleting"), function() {
                                    Storage.deleteShot(id)
                                    page.refresh()
                                })
                            }
                        }
                    }
                }
            }

            Item { width: 1; height: Theme.paddingLarge }
        }

        VerticalScrollDecorator { }
    }
}
