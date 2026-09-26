import QtQuick 2.0
import Sailfish.Silica 1.0
import "../Storage.js" as Storage
import "../Gear.js" as Gear
import ".." 1.0
import "../components"

// A camera is described by the two questions a light meter needs answered:
// can the lens come off, and if it can, is the shutter in the body or in each
// lens. That decides where the speeds and apertures are written down.
//
//   fixed lens              speeds and apertures on the camera   (type 0)
//   shutter in the body     speeds on the camera, apertures per lens (type 1)
//   shutter in each lens    speeds and apertures per lens         (type 2)
//
// One line per question, each only once the one before it makes it matter.
// A single choice is a dropdown; a list of values opens the plate.

Page {
    id: page
    allowedOrientations: Orientation.Portrait

    property int editId: -1

    // -1 = not answered yet
    property int interchangeable: -1   // 0 no, 1 yes
    property int shutterInLens: -1     // 0 in the body, 1 in each lens

    readonly property int typeIndex: {
        if (interchangeable === 0) return 0
        if (interchangeable === 1 && shutterInLens === 0) return 1
        if (interchangeable === 1 && shutterInLens === 1) return 2
        return -1
    }

    property var speeds: []
    property var apertures: []
    property string mount: ""

    readonly property bool needsSpeeds: typeIndex === 0 || typeIndex === 1
    readonly property bool needsApertures: typeIndex === 0
    readonly property bool needsMount: typeIndex === 1 || typeIndex === 2

    readonly property bool canSave: typeIndex !== -1
                                    && cameraName.text.trim().length > 0
                                    && (!needsMount || mount.length > 0)
                                    && (!needsSpeeds || speeds.length > 0)
                                    && (!needsApertures || apertures.length > 0)

    function paint() { FiatLuxTheme.applyPalette(page) }
    Connections {
        target: FiatLuxTheme
        onAmbientChanged: page.paint()
    }

    Component.onCompleted: {
        paint()
        if (editId >= 0) {
            var c = Storage.getCamera(editId)
            if (c) {
                cameraName.text = c.name
                mount = c.mount || ""
                interchangeable = c.type === 0 ? 0 : 1
                shutterInLens = c.type === 2 ? 1 : (c.type === 1 ? 0 : -1)
                speeds = Gear.speedsForStorage(Gear.splitList(c.bodySpeeds))
                apertures = Gear.sortApertures(Gear.splitList(c.apertures))
            }
        }
        syncTimer.restart()
    }

    // A ComboBox takes its index from its menu items, so it is set a beat
    // after they exist.
    Timer {
        id: syncTimer
        interval: 0
        onTriggered: {
            lensCombo.currentIndex = page.interchangeable
            shutterCombo.currentIndex = page.shutterInLens
        }
    }

    function editSpeeds() {
        var d = pageStack.push(Qt.resolvedUrl("PlateDialog.qml"),
                               { kind: "speeds", selected: page.speeds, owner: cameraName.text })
        d.accepted.connect(function() { page.speeds = d.selected })
    }

    function editApertures() {
        var d = pageStack.push(Qt.resolvedUrl("PlateDialog.qml"),
                               { kind: "apertures", selected: page.apertures, owner: cameraName.text })
        d.accepted.connect(function() { page.apertures = d.selected })
    }

    function editMount() {
        var p = pageStack.push(Qt.resolvedUrl("MountPage.qml"), { current: page.mount })
        p.picked.connect(function(m) { page.mount = m })
    }

    function save() {
        var name = cameraName.text.trim()
        var s = page.needsSpeeds ? Gear.speedsForStorage(page.speeds).join(",") : ""
        var a = page.needsApertures ? Gear.sortApertures(page.apertures).join(",") : ""
        var m = page.needsMount ? page.mount : ""
        if (page.editId >= 0)
            Storage.updateCamera(page.editId, name, page.typeIndex, m, s, a)
        else
            Storage.addCamera(name, page.typeIndex, m, s, a)
        app.reloadCameras()
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
                title: page.editId >= 0 ? qsTr("edit camera") : qsTr("add camera")
                subtitle: "fiat lux"
            }

            TextField {
                id: cameraName
                width: parent.width
                label: qsTr("Camera name")
                placeholderText: qsTr("e.g. Yashica B")
                color: FiatLuxTheme.primaryText
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }

            // ---- question one ----
            ComboBox {
                id: lensCombo
                width: parent.width
                label: qsTr("lens")
                value: currentIndex < 0 ? qsTr("choose") : (currentItem ? currentItem.text : "")
                description: page.interchangeable === 0
                             ? qsTr("TLRs like the Yashica Mat, and most compacts, have a built-in lens.")
                             : ""
                menu: ContextMenu {
                    highlightColor: FiatLuxTheme.accent
                    MenuItem {
                        text: qsTr("built in")
                        color: FiatLuxTheme.primaryText
                        onClicked: page.interchangeable = 0
                    }
                    MenuItem {
                        text: qsTr("interchangeable")
                        color: FiatLuxTheme.primaryText
                        onClicked: page.interchangeable = 1
                    }
                }
            }

            // ---- question two ----
            ComboBox {
                id: shutterCombo
                visible: page.interchangeable === 1
                width: parent.width
                label: qsTr("shutter")
                value: currentIndex < 0 ? qsTr("choose") : (currentItem ? currentItem.text : "")
                description: page.shutterInLens === 0
                             ? qsTr("SLRs and most rangefinders, like the Pentax MX or a Leica M.")
                             : page.shutterInLens === 1
                               ? qsTr("Leaf shutters: Hasselblad V, Mamiya RB67, large format.")
                               : ""
                menu: ContextMenu {
                    highlightColor: FiatLuxTheme.accent
                    MenuItem {
                        text: qsTr("in the body")
                        color: FiatLuxTheme.primaryText
                        onClicked: page.shutterInLens = 0
                    }
                    MenuItem {
                        text: qsTr("in each lens")
                        color: FiatLuxTheme.primaryText
                        onClicked: page.shutterInLens = 1
                    }
                }
            }

            ValueButton {
                visible: page.needsMount
                width: parent.width
                label: qsTr("mount")
                value: page.mount !== "" ? page.mount : qsTr("choose")
                description: qsTr("Lenses with the same mount fit this camera.")
                onClicked: page.editMount()
            }

            ValueButton {
                visible: page.needsSpeeds
                width: parent.width
                label: page.typeIndex === 0 ? qsTr("shutter speeds") : qsTr("speeds on the body")
                value: page.speeds.length > 0 ? Gear.speedSummary(page.speeds) : qsTr("choose")
                description: page.speeds.length > 0 ? Gear.speedCount(page.speeds) : qsTr("Only the ones on the dial.")
                onClicked: page.editSpeeds()
            }

            ValueButton {
                visible: page.needsApertures
                width: parent.width
                label: qsTr("apertures")
                value: page.apertures.length > 0 ? Gear.apertureSummary(page.apertures) : qsTr("choose")
                description: page.apertures.length > 0 ? Gear.apertureCount(page.apertures) : ""
                onClicked: page.editApertures()
            }

            FormNote {
                visible: page.typeIndex === 1 || page.typeIndex === 2
                height: visible ? implicitHeight + Theme.paddingLarge : 0
                verticalAlignment: Text.AlignBottom
                text: page.typeIndex === 1
                      ? qsTr("Apertures belong to each lens. Add them under Lenses with the same mount.")
                      : qsTr("Each lens carries its own speeds and apertures. Add them under Lenses with the same mount.")
            }

            Item { width: 1; height: Theme.paddingLarge }

            FiatButton {
                text: page.editId >= 0 ? qsTr("save changes") : qsTr("save camera")
                enabled: page.canSave
                onClicked: page.save()
            }

            Item { width: 1; height: Theme.paddingLarge }
        }

        VerticalScrollDecorator { }
    }
}
