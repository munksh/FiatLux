import QtQuick 2.0
import Sailfish.Silica 1.0
import "../Gear.js" as Gear
import ".."

// The relative dial.
//
// The apertures run along the top, spaced by stops: f/N sits at log2(N^2).
// The camera's own speeds run along the bottom, each at the stop where it
// pairs with an aperture at the metered light: at EV (for this film speed) a
// time t pairs with the aperture at EV + log2(t). So a speed sits straight
// under the aperture it gives a correct exposure with, and a speed between two
// apertures sits between them -- the gaps in an old camera's speeds are
// visible at a glance.
//
// The aperture under the centre line is the chosen one, and the small
// triangle marks the exact exposure for it. The nearest speed the camera
// really has is chosen for you; tap another speed to go over or under on
// purpose. Drag sideways to choose another aperture; it snaps.
//
// Labels that would run into each other give way: the chosen one never, the
// rest by distance from it. A hidden value keeps its tick.

Item {
    id: dial

    property var apertures: []          // strings, widest first
    property var speeds: []             // strings, any order, may hold "B"
    property real evIso: 0              // EV at the film's speed
    property bool live: false           // there is a reading
    property int apIndex: 0
    property int chosenSpeed: -1        // -1: the nearest

    // Tell the page something was chosen by hand.
    signal chosen()

    readonly property int nearestSpeed: {
        if (!live || apertures.length === 0) return -1
        var p = apPos(apIndex)
        var best = -1, d = 1e9
        for (var i = 0; i < speeds.length; i++) {
            var q = spPos(i)
            if (isNaN(q)) continue
            if (Math.abs(q - p) < d) { d = Math.abs(q - p); best = i }
        }
        return best
    }
    readonly property int pickedSpeed: !live ? -1
                                      : (chosenSpeed >= 0 && chosenSpeed < speeds.length ? chosenSpeed : nearestSpeed)
    // > 0: the chosen speed is longer than the exact one, so over.
    readonly property real diffStops: pickedSpeed < 0 ? 0 : spPos(pickedSpeed) - apPos(apIndex)
    readonly property bool deliberate: pickedSpeed >= 0 && pickedSpeed !== nearestSpeed

    readonly property real stopWidth: width * 0.17
    readonly property real p0: apertures.length > 0 && apIndex >= 0 && apIndex < apertures.length ? apPos(apIndex) : 0

    // Where the centre of the dial is, in stops. Follows p0, animated, and
    // follows the finger while dragging.
    property real centre: 0
    property bool animate: false
    Behavior on centre {
        enabled: dial.animate
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }
    onP0Changed: centre = p0
    Component.onCompleted: {
        centre = p0
        animate = true
        relayout()
    }

    function apPos(i) {
        var n = parseFloat(apertures[i])
        return n > 0 ? Math.log(n * n) / Math.LN2 : NaN
    }
    function spPos(i) {
        var t = Gear.parseSpeed(speeds[i])
        return (t === null || !(t > 0)) ? NaN : evIso + Math.log(t) / Math.LN2
    }

    // ---- which labels show ----

    property var apShown: []
    property var spShown: []

    function place(items, widthOf, pad) {
        items.sort(function(a, b) { return a.pri - b.pri })
        var kept = []
        for (var k = 0; k < items.length; k++) {
            var it = items[k]
            var ok = true
            for (var j = 0; j < kept.length; j++) {
                var need = (widthOf(it.i) + widthOf(kept[j].i)) / 2 + pad
                if (Math.abs(kept[j].x - it.x) < need) { ok = false; break }
            }
            if (ok) kept.push(it)
        }
        return kept
    }

    function relayout() {
        var i
        var aItems = []
        for (i = 0; i < apertures.length; i++) {
            var pa = apPos(i)
            if (isNaN(pa)) continue
            aItems.push({ i: i, x: pa * stopWidth, pri: i === apIndex ? -1 : Math.abs(i - apIndex) })
        }
        var aKept = place(aItems, function(k) {
            var it = apRepeater.itemAt(k)
            return it ? it.implicitWidth : Theme.itemSizeSmall
        }, Theme.paddingMedium)
        var a = []
        for (i = 0; i < apertures.length; i++) a.push(false)
        for (i = 0; i < aKept.length; i++) a[aKept[i].i] = true
        apShown = a

        var sItems = []
        if (live) {
            for (i = 0; i < speeds.length; i++) {
                var ps = spPos(i)
                if (isNaN(ps)) continue
                sItems.push({ i: i, x: ps * stopWidth, pri: i === pickedSpeed ? -1 : Math.abs(ps - p0) })
            }
        }
        var sKept = place(sItems, function(k) {
            var it = spRepeater.itemAt(k)
            return it ? it.implicitWidth : Theme.itemSizeSmall
        }, Theme.paddingMedium)
        var s = []
        for (i = 0; i < speeds.length; i++) s.push(false)
        for (i = 0; i < sKept.length; i++) s[sKept[i].i] = true
        spShown = s
    }

    Timer {
        id: relayoutTimer
        interval: 0
        onTriggered: dial.relayout()
    }
    onAperturesChanged: relayoutTimer.restart()
    onSpeedsChanged: relayoutTimer.restart()
    onEvIsoChanged: relayoutTimer.restart()
    onLiveChanged: relayoutTimer.restart()
    onApIndexChanged: relayoutTimer.restart()
    onPickedSpeedChanged: relayoutTimer.restart()
    onWidthChanged: relayoutTimer.restart()

    function xAt(pos) { return width / 2 + (pos - centre) * stopWidth }

    clip: true
    height: apRow.height + axisGap * 2 + spRow.height + triangleSize + Theme.paddingSmall * 2

    readonly property real axisGap: Theme.paddingMedium
    readonly property real triangleSize: Theme.paddingMedium * 1.2

    // ---- the apertures ----
    Item {
        id: apRow
        width: parent.width
        height: Theme.fontSizeLarge * 1.35
        y: Theme.paddingSmall

        Repeater {
            id: apRepeater
            model: dial.apertures
            delegate: Label {
                readonly property real pos: dial.apPos(index)
                readonly property bool sel: index === dial.apIndex
                visible: !isNaN(pos) && (dial.apShown[index] === true)
                x: dial.xAt(pos) - width / 2
                anchors.bottom: parent.bottom
                text: "f/" + modelData
                color: sel ? FiatLuxTheme.primaryText : FiatLuxTheme.secondaryText
                font.pixelSize: sel ? Theme.fontSizeLarge : Theme.fontSizeMedium
                font.family: FiatLuxTheme.serif
            }
        }
    }

    // ---- the axis, a tick per aperture above it and per speed below ----
    Item {
        id: axis
        width: parent.width
        y: apRow.y + apRow.height + dial.axisGap
        height: 1

        Rectangle {
            width: parent.width
            height: Math.max(1, Math.round(Theme.paddingSmall / 6))
            color: FiatLuxTheme.innerBorder
        }
        Repeater {
            model: dial.apertures
            delegate: Rectangle {
                readonly property real pos: dial.apPos(index)
                visible: !isNaN(pos)
                x: dial.xAt(pos) - width / 2
                y: -height
                width: Math.max(1, Math.round(Theme.paddingSmall / 6))
                height: Theme.paddingSmall * 1.5
                color: FiatLuxTheme.innerBorder
            }
        }
        Repeater {
            model: dial.live ? dial.speeds : []
            delegate: Rectangle {
                readonly property real pos: dial.spPos(index)
                visible: !isNaN(pos)
                x: dial.xAt(pos) - width / 2
                y: 0
                width: Math.max(1, Math.round(Theme.paddingSmall / 6))
                height: Theme.paddingSmall * 1.5
                color: index === dial.pickedSpeed ? FiatLuxTheme.accent : FiatLuxTheme.innerBorder
            }
        }
    }

    // The centre line: from under the chosen aperture down to the axis.
    Rectangle {
        x: dial.width / 2 - width / 2
        y: apRow.y + apRow.height
        width: Math.max(2, Math.round(Theme.paddingSmall / 4))
        height: axis.y - y + Theme.paddingSmall
        color: FiatLuxTheme.accent
        opacity: 0.6
    }

    // ---- the speeds ----
    Item {
        id: spRow
        width: parent.width
        y: axis.y + dial.axisGap
        height: Theme.fontSizeMedium * 1.35

        Repeater {
            id: spRepeater
            model: dial.speeds
            delegate: Label {
                readonly property real pos: dial.spPos(index)
                readonly property bool sel: index === dial.pickedSpeed
                visible: dial.live && !isNaN(pos) && (dial.spShown[index] === true)
                x: dial.xAt(pos) - width / 2
                anchors.top: parent.top
                text: modelData
                color: sel ? FiatLuxTheme.accent : FiatLuxTheme.secondaryText
                font.pixelSize: sel ? Theme.fontSizeMedium : Theme.fontSizeSmall
                font.bold: sel
            }
        }

        Label {
            anchors.centerIn: parent
            visible: !dial.live
            text: qsTr("measure to pair the speeds")
            color: FiatLuxTheme.secondaryText
            font.pixelSize: Theme.fontSizeExtraSmall
            font.family: FiatLuxTheme.serif
            font.italic: true
        }
    }

    // The exact exposure for the chosen aperture: where the speed would be
    // if the camera had it.
    Canvas {
        id: triangle
        visible: dial.live
        width: dial.triangleSize * 1.4
        height: dial.triangleSize
        x: dial.xAt(dial.p0) - width / 2
        y: spRow.y + spRow.height + Theme.paddingSmall / 2
        property color fill: FiatLuxTheme.accent
        onFillChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.beginPath()
            ctx.moveTo(width / 2, 0)
            ctx.lineTo(width, height)
            ctx.lineTo(0, height)
            ctx.closePath()
            ctx.fillStyle = fill
            ctx.fill()
        }
    }

    // ---- hands ----
    MouseArea {
        anchors.fill: parent
        preventStealing: true

        property real startX: 0
        property real startCentre: 0
        property bool dragging: false

        onPressed: {
            startX = mouse.x
            startCentre = dial.centre
            dragging = false
        }
        onPositionChanged: {
            var dx = mouse.x - startX
            if (!dragging && Math.abs(dx) > Theme.paddingLarge) dragging = true
            if (dragging && dial.apertures.length > 0) {
                dial.animate = false
                dial.centre = startCentre - dx / dial.stopWidth
            }
        }
        onReleased: {
            if (dragging) {
                dragging = false
                // Snap to the aperture now nearest the centre.
                var best = dial.apIndex, d = 1e9
                for (var i = 0; i < dial.apertures.length; i++) {
                    var q = Math.abs(dial.apPos(i) - dial.centre)
                    if (q < d) { d = q; best = i }
                }
                dial.animate = true
                dial.chosenSpeed = -1
                dial.apIndex = best
                dial.centre = dial.p0
                dial.chosen()
                return
            }
            dial.tapAt(mouse.x, mouse.y)
        }
        onCanceled: {
            dragging = false
            dial.animate = true
            dial.centre = dial.p0
        }
    }

    function tapAt(mx, my) {
        var i, best = -1, d = 1e9
        if (my > axis.y) {
            if (!live) return
            for (i = 0; i < speeds.length; i++) {
                if (spShown[i] !== true) continue
                var it = spRepeater.itemAt(i)
                var q = Math.abs(xAt(spPos(i)) - mx)
                var reach = (it ? it.width / 2 : 0) + Theme.paddingLarge
                if (q < reach && q < d) { d = q; best = i }
            }
            if (best < 0) return
            chosenSpeed = best === nearestSpeed ? -1 : best
            chosen()
            return
        }
        for (i = 0; i < apertures.length; i++) {
            var qa = Math.abs(xAt(apPos(i)) - mx)
            if (qa < stopWidth / 2 && qa < d) { d = qa; best = i }
        }
        if (best < 0 || best === apIndex) return
        chosenSpeed = -1
        apIndex = best
        chosen()
    }
}
