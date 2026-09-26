import QtQuick 2.0
import Sailfish.Silica 1.0
import "../Storage.js" as Storage
import "../Gear.js" as Gear
import ".." 1.0
import "../components"

// A lens for a camera whose lens comes off. It finds its cameras by mount.
//
// Speeds only when the shutter is in the lens (a leaf shutter: Hasselblad V,
// Mamiya RB67, large format). An SLR or rangefinder lens leaves them to the
// body, so for those the question is asked and the speeds are never shown.
// When the mount already belongs to one of your cameras, the answer is taken
// from that camera; it can still be changed.

Page {
    id: page
    allowedOrientations: Orientation.Portrait

    property int editId: -1
    // Optional: the mount, when opened from a camera.
    property string presetMount: ""

    property string mount: ""
    property var apertures: []
    property var speeds: []

    // -1 not answered, 0 in the camera, 1 in the lens (a leaf shutter)
    property int shutterInLens: -1

    readonly property bool canSave: lensName.text.trim().length > 0 && mount.length > 0
                                    && apertures.length > 0 && shutterInLens >= 0
                                    && (shutterInLens === 0 || speeds.length > 0)

    // What the cameras with this mount say: 1 if one has its shutter in each
    // lens, 0 if one has it in the body, -1 if none has this mount.
    function shutterFromCameras(m) {
        var answer = -1
        for (var i = 0; i < app.cameraModel.count; i++) {
            var c = app.cameraModel.get(i)
            if (c.mount !== m) continue
            if (c.type === 2) return 1
            if (c.type === 1) answer = 0
        }
        return answer
    }

    onMountChanged: {
        if (page.editId >= 0 && page.shutterInLens >= 0) return
        var guess = shutterFromCameras(page.mount)
        if (guess >= 0) {
            page.shutterInLens = guess
            syncTimer.restart()
        }
    }

    // A ComboBox takes its index from its menu items, so it is set a beat
    // after they exist.
    Timer {
        id: syncTimer
        interval: 0
        onTriggered: shutterCombo.currentIndex = page.shutterInLens
    }

    function paint() { FiatLuxTheme.applyPalette(page) }
    Connections {
        target: FiatLuxTheme
        onAmbientChanged: page.paint()
    }

    Component.onCompleted: {
        paint()
        if (presetMount.length > 0) mount = presetMount
        if (editId >= 0) {
            var l = Storage.getLens(editId)
            if (l) {
                lensName.text = l.name
                mount = l.mount || ""
                apertures = Gear.sortApertures(Gear.splitList(l.apertures))
                speeds = Gear.speedsForStorage(Gear.splitList(l.speeds))
                shutterInLens = speeds.length > 0 ? 1 : 0
            }
        }
        syncTimer.restart()
    }

    function editMount() {
        var p = pageStack.push(Qt.resolvedUrl("MountPage.qml"), { current: page.mount })
        p.picked.connect(function(m) { page.mount = m })
    }

    function editApertures() {
        var d = pageStack.push(Qt.resolvedUrl("PlateDialog.qml"),
                               { kind: "apertures", selected: page.apertures, owner: lensName.text })
        d.accepted.connect(function() { page.apertures = d.selected })
    }

    function editSpeeds() {
        var d = pageStack.push(Qt.resolvedUrl("PlateDialog.qml"),
                               { kind: "speeds", selected: page.speeds, owner: lensName.text })
        d.accepted.connect(function() { page.speeds = d.selected })
    }

    function save() {
        var name = lensName.text.trim()
        var a = Gear.sortApertures(page.apertures).join(",")
        var s = page.shutterInLens === 1 ? Gear.speedsForStorage(page.speeds).join(",") : ""
        if (page.editId >= 0)
            Storage.updateLens(page.editId, name, page.mount, a, s)
        else
            Storage.addLens(name, page.mount, a, s)
        app.reloadLenses()
        pageStack.pop()
    }

    PaperBackground { }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: page.width

            PageHead {
                title: page.editId >= 0 ? qsTr("edit lens") : qsTr("add lens")
                subtitle: "fiat lux"
            }

            TextField {
                id: lensName
                width: parent.width
                label: qsTr("Lens name")
                placeholderText: qsTr("e.g. SMC Pentax-M 50mm f/1.7")
                color: FiatLuxTheme.primaryText
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }

            ValueButton {
                width: parent.width
                label: qsTr("mount")
                value: page.mount !== "" ? page.mount : qsTr("choose")
                description: qsTr("The same mount as the camera it fits.")
                onClicked: page.editMount()
            }

            ValueButton {
                width: parent.width
                label: qsTr("apertures")
                value: page.apertures.length > 0 ? Gear.apertureSummary(page.apertures) : qsTr("choose")
                description: page.apertures.length > 0 ? Gear.apertureCount(page.apertures) : ""
                onClicked: page.editApertures()
            }

            ComboBox {
                id: shutterCombo
                width: parent.width
                label: qsTr("shutter")
                value: currentIndex < 0 ? qsTr("choose") : (currentItem ? currentItem.text : "")
                description: page.shutterInLens === 0
                             ? qsTr("SLRs and most rangefinders: the body sets the speed.")
                             : page.shutterInLens === 1
                               ? qsTr("A leaf shutter: Hasselblad V, Mamiya RB67, large format.")
                               : ""
                menu: ContextMenu {
                    highlightColor: FiatLuxTheme.accent
                    MenuItem {
                        text: qsTr("in the camera")
                        color: FiatLuxTheme.primaryText
                        onClicked: page.shutterInLens = 0
                    }
                    MenuItem {
                        text: qsTr("in the lens")
                        color: FiatLuxTheme.primaryText
                        onClicked: page.shutterInLens = 1
                    }
                }
            }

            ValueButton {
                visible: page.shutterInLens === 1
                width: parent.width
                label: qsTr("shutter speeds")
                value: page.speeds.length > 0 ? Gear.speedSummary(page.speeds) : qsTr("choose")
                description: page.speeds.length > 0 ? Gear.speedCount(page.speeds) : qsTr("The ones on the lens's own dial.")
                onClicked: page.editSpeeds()
            }

            Item { width: 1; height: Theme.paddingLarge }

            FiatButton {
                text: page.editId >= 0 ? qsTr("save changes") : qsTr("save lens")
                enabled: page.canSave
                onClicked: page.save()
            }

            Item { width: 1; height: Theme.paddingLarge }
        }

        VerticalScrollDecorator { }
    }
}
