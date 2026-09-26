import QtQuick 2.0
import Sailfish.Silica 1.0
import "../Storage.js" as Storage
import ".." 1.0

// A camera is described by the two questions a light meter needs answered:
// can the lens come off, and if it can, is the shutter in the body or in each
// lens. That decides where the speeds and apertures are written down.
//
//   fixed lens              speeds and apertures on the camera   (type 0)
//   shutter in the body     speeds on the camera, apertures per lens (type 1)
//   shutter in each lens    speeds and apertures per lens         (type 2)

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

    property int editId: -1

    readonly property var allSpeeds: ["1/1000","1/500","1/400","1/300","1/250","1/200","1/125","1/100","1/60","1/50","1/30","1/25","1/15","1/10","1/8","1/5","1/4","1/2","1\"","B"]
    readonly property var allApertures: ["1","1.2","1.4","1.7","1.8","2","2.8","3.5","4","4.5","5.6","6.3","8","11","16","22","32"]

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

    readonly property bool needsSpeeds: typeIndex === 0 || typeIndex === 1
    readonly property bool needsApertures: typeIndex === 0
    readonly property bool needsMount: typeIndex === 1 || typeIndex === 2

    readonly property bool canSave: typeIndex !== -1
                                    && cameraName.text.length > 0
                                    && (!needsMount || mountField.text.length > 0)
                                    && (!needsSpeeds || speeds.length > 0)
                                    && (!needsApertures || apertures.length > 0)

    property var knownMounts: []

    Component.onCompleted: {
        knownMounts = Storage.mounts()
        if (editId >= 0) {
            var c = Storage.getCamera(editId)
            if (c) {
                cameraName.text = c.name
                mountField.text = c.mount
                interchangeable = c.type === 0 ? 0 : 1
                shutterInLens = c.type === 2 ? 1 : (c.type === 1 ? 0 : -1)
                speeds = c.bodySpeeds.length > 0 ? c.bodySpeeds.split(",") : []
                apertures = c.apertures.length > 0 ? c.apertures.split(",") : []
            }
        }
    }

    function toggled(list, value) {
        var out = list.slice()
        var i = out.indexOf(value)
        if (i === -1) out.push(value)
        else out.splice(i, 1)
        return out
    }

    // Kept in the order of the master list, whatever order they were tapped in.
    function ordered(list, master) {
        return master.filter(function(v) { return list.indexOf(v) !== -1 })
    }

    // ---- a selectable pill ----
    Component {
        id: choicePill
        BackgroundItem {
            id: pill
            property string label: ""
            property bool selected: false
            signal chosen()
            width: pillText.implicitWidth + Theme.paddingLarge * 2
            height: pillText.implicitHeight + Theme.paddingMedium * 1.5
            highlightedColor: "transparent"
            onClicked: pill.chosen()
            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: pill.selected || pill.highlighted ? FiatLuxTheme.pillFillActive : FiatLuxTheme.pillFill
                border.color: pill.selected ? FiatLuxTheme.pillBorderActive : FiatLuxTheme.pillBorder
                border.width: 1
            }
            Text {
                id: pillText
                anchors.centerIn: parent
                text: pill.label
                color: pill.selected ? FiatLuxTheme.accent : FiatLuxTheme.primaryText
                font.pixelSize: Theme.fontSizeSmall
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

            Item { width: 1; height: Theme.paddingLarge }

            Item {
                width: parent.width; height: Theme.itemSizeLarge
                Text {
                    anchors.centerIn: parent
                    text: page.editId >= 0 ? qsTr("edit camera") : qsTr("add camera")
                    color: FiatLuxTheme.primaryText
                    font.pixelSize: Theme.fontSizeLarge
                    font.family: FiatLuxTheme.serif
                    font.italic: true
                }
            }

            CardSection {
                title: qsTr("camera")
                TextField {
                    id: cameraName
                    width: parent.width
                    placeholderText: qsTr("e.g. Pentax MX")
                    label: qsTr("Camera name")
                    color: FiatLuxTheme.primaryText
                }
            }

            // ---- question one ----
            CardSection {
                title: qsTr("can you change the lens?")
                Flow {
                    width: parent.width
                    spacing: Theme.paddingSmall
                    Loader {
                        sourceComponent: choicePill
                        onLoaded: {
                            item.label = qsTr("no, it is built in")
                            item.selected = Qt.binding(function() { return page.interchangeable === 0 })
                            item.chosen.connect(function() { page.interchangeable = 0 })
                        }
                    }
                    Loader {
                        sourceComponent: choicePill
                        onLoaded: {
                            item.label = qsTr("yes")
                            item.selected = Qt.binding(function() { return page.interchangeable === 1 })
                            item.chosen.connect(function() { page.interchangeable = 1 })
                        }
                    }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: qsTr("TLRs like the Yashica Mat, and most compacts, have a built-in lens.")
                    color: FiatLuxTheme.secondaryText
                    font.pixelSize: Theme.fontSizeExtraSmall
                }
            }

            // ---- question two ----
            CardSection {
                visible: page.interchangeable === 1
                title: qsTr("where is the shutter?")
                Flow {
                    width: parent.width
                    spacing: Theme.paddingSmall
                    Loader {
                        sourceComponent: choicePill
                        onLoaded: {
                            item.label = qsTr("in the body")
                            item.selected = Qt.binding(function() { return page.shutterInLens === 0 })
                            item.chosen.connect(function() { page.shutterInLens = 0 })
                        }
                    }
                    Loader {
                        sourceComponent: choicePill
                        onLoaded: {
                            item.label = qsTr("in each lens")
                            item.selected = Qt.binding(function() { return page.shutterInLens === 1 })
                            item.chosen.connect(function() { page.shutterInLens = 1 })
                        }
                    }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: qsTr("In the body: SLRs and most rangefinders, like the Pentax MX or a Leica M. In each lens: Hasselblad V, Mamiya RB67, large format.")
                    color: FiatLuxTheme.secondaryText
                    font.pixelSize: Theme.fontSizeExtraSmall
                }
            }

            // ---- mount ----
            CardSection {
                visible: page.needsMount
                title: qsTr("lens mount")
                TextField {
                    id: mountField
                    width: parent.width
                    placeholderText: qsTr("e.g. K-mount, M42, Hasselblad V")
                    label: qsTr("Lenses with the same mount fit this camera")
                    color: FiatLuxTheme.primaryText
                }
                Flow {
                    visible: page.knownMounts.length > 0
                    width: parent.width
                    spacing: Theme.paddingSmall
                    Repeater {
                        model: page.knownMounts
                        delegate: Loader {
                            sourceComponent: choicePill
                            onLoaded: {
                                item.label = modelData
                                item.selected = Qt.binding(function() { return mountField.text === modelData })
                                item.chosen.connect(function() { mountField.text = modelData })
                            }
                        }
                    }
                }
            }

            // ---- speeds ----
            CardSection {
                visible: page.needsSpeeds
                title: page.typeIndex === 0 ? qsTr("shutter speeds") : qsTr("shutter speeds on the body")
                Flow {
                    width: parent.width
                    spacing: Theme.paddingSmall
                    Repeater {
                        model: page.allSpeeds
                        delegate: Loader {
                            sourceComponent: choicePill
                            onLoaded: {
                                item.label = modelData
                                item.selected = Qt.binding(function() { return page.speeds.indexOf(modelData) !== -1 })
                                item.chosen.connect(function() {
                                    page.speeds = page.ordered(page.toggled(page.speeds, modelData), page.allSpeeds)
                                })
                            }
                        }
                    }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: qsTr("Only the ones on the dial. Lux only suggests speeds you can set.")
                    color: FiatLuxTheme.secondaryText
                    font.pixelSize: Theme.fontSizeExtraSmall
                }
            }

            // ---- apertures (fixed lens only) ----
            CardSection {
                visible: page.needsApertures
                title: qsTr("apertures")
                Flow {
                    width: parent.width
                    spacing: Theme.paddingSmall
                    Repeater {
                        model: page.allApertures
                        delegate: Loader {
                            sourceComponent: choicePill
                            onLoaded: {
                                item.label = "f/" + modelData
                                item.selected = Qt.binding(function() { return page.apertures.indexOf(modelData) !== -1 })
                                item.chosen.connect(function() {
                                    page.apertures = page.ordered(page.toggled(page.apertures, modelData), page.allApertures)
                                })
                            }
                        }
                    }
                }
            }

            Text {
                visible: page.typeIndex === 1 || page.typeIndex === 2
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: page.typeIndex === 1
                      ? qsTr("Apertures belong to each lens. Add the lenses on the Lenses page with the same mount.")
                      : qsTr("Each lens carries its own speeds and apertures. Add them on the Lenses page with the same mount.")
                color: FiatLuxTheme.secondaryText
                font.pixelSize: Theme.fontSizeExtraSmall
            }

            BackgroundItem {
                id: saveBtn
                width: parent.width; height: Theme.itemSizeLarge
                enabled: page.canSave
                opacity: enabled ? 1.0 : 0.35
                onClicked: {
                    var s = page.needsSpeeds ? page.speeds.join(",") : ""
                    var a = page.needsApertures ? page.apertures.join(",") : ""
                    var m = page.needsMount ? mountField.text : ""
                    if (page.editId >= 0)
                        Storage.updateCamera(page.editId, cameraName.text, page.typeIndex, m, s, a)
                    else
                        Storage.addCamera(cameraName.text, page.typeIndex, m, s, a)
                    app.reloadCameras()
                    pageStack.pop()
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    height: Theme.itemSizeMedium; radius: Theme.paddingLarge
                    color: saveBtn.highlighted ? FiatLuxTheme.amberStrong : FiatLuxTheme.amber
                    Text {
                        anchors.centerIn: parent
                        text: page.editId >= 0 ? qsTr("save changes") : qsTr("save camera")
                        color: FiatLuxTheme.onAccent
                        font.pixelSize: Theme.fontSizeMedium
                        font.family: FiatLuxTheme.serif; font.italic: true; font.bold: true
                    }
                }
            }

            Item { width: 1; height: Theme.paddingLarge }
        }
    }
}
