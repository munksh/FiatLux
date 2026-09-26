import QtQuick 2.0
import Sailfish.Silica 1.0
import "../Storage.js" as Storage
import "../Gear.js" as Gear
import ".." 1.0
import "../components"

// A lens for a camera whose lens comes off. It finds its cameras by mount.
// Speeds only when the shutter is in the lens (a leaf shutter: Hasselblad V,
// Mamiya RB67, large format); an SLR lens leaves them to the body.

Page {
    id: page
    allowedOrientations: Orientation.Portrait

    property int editId: -1
    // Optional: the mount, when opened from a camera.
    property string presetMount: ""

    property string mount: ""
    property var apertures: []
    property var speeds: []

    readonly property bool canSave: lensName.text.trim().length > 0 && mount.length > 0 && apertures.length > 0

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
            }
        }
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
                               { kind: "speeds", selected: page.speeds, owner: lensName.text, allowEmpty: true })
        d.accepted.connect(function() { page.speeds = d.selected })
    }

    function save() {
        var name = lensName.text.trim()
        var a = Gear.sortApertures(page.apertures).join(",")
        var s = Gear.speedsForStorage(page.speeds).join(",")
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

            ValueButton {
                width: parent.width
                label: qsTr("shutter speeds")
                value: page.speeds.length > 0 ? Gear.speedSummary(page.speeds) : qsTr("none")
                description: page.speeds.length > 0
                             ? Gear.speedCount(page.speeds)
                             : qsTr("Only for a lens with its own shutter. An SLR lens leaves them to the body.")
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
