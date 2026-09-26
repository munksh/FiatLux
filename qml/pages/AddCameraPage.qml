import QtQuick 2.0
import Sailfish.Silica 1.0
import "../Storage.js" as Storage
import ".." 1.0

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

    // If editId >= 0 we're editing; else adding
    property int editId: -1
    property var allSpeeds: ["1/1000","1/500","1/300","1/250","1/125","1/100","1/60","1/50","1/30","1/15","1/8","1/4","1/2","1\"","B"]
    property var bodySpeeds: []
    property int typeIndex: -1
    property var typeLabels: ["Fixed (built-in lens)", "SLR / Rangefinder", "Leaf shutter"]
    property var knownMounts: []
    property int speedGen: 0   // bump to rebuild speed pills with new preselection
    property bool canSave: typeIndex !== -1 && cameraName.text.length > 0 && mountField.text.length > 0

    Component.onCompleted: {
        knownMounts = Storage.mounts()
        if (editId >= 0) {
            var c = Storage.getCamera(editId)
            if (c) {
                cameraName.text = c.name
                mountField.text = c.mount
                typeIndex = c.type
                bodySpeeds = (c.bodySpeeds && c.bodySpeeds.length > 0) ? c.bodySpeeds.split(",") : []
                speedGen++
            }
        }
    }

    function isSpeedSelected(s) { return bodySpeeds.indexOf(s) !== -1 }

    // Reusable pill
    Component {
        id: pillComponent
        Rectangle {
            property bool selected: false
            property string label: ""
            property var onToggle
            width: pillLabel.implicitWidth + Theme.paddingLarge * 2
            height: pillLabel.implicitHeight + Theme.paddingMedium
            radius: height / 2
            color: selected ? FiatLuxTheme.amberMed : "transparent"
            border.color: selected ? FiatLuxTheme.amber : FiatLuxTheme.rim
            border.width: selected ? 2 : 1
            Text {
                id: pillLabel
                anchors.centerIn: parent
                text: parent.label
                color: parent.selected ? FiatLuxTheme.amber : FiatLuxTheme.primaryText
                font.pixelSize: Theme.fontSizeSmall
            }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    parent.selected = !parent.selected
                    if (parent.onToggle) parent.onToggle(parent.selected)
                }
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

            // Clearance for the system status bar / notch
            Item { width: 1; height: Theme.paddingLarge }

            Item {
                width: parent.width; height: Theme.itemSizeLarge
                Text {
                    anchors.centerIn: parent
                    text: editId >= 0 ? "edit camera" : "add camera"
                    color: FiatLuxTheme.primaryText
                    font.pixelSize: Theme.fontSizeLarge
                    font.family: FiatLuxTheme.serif
                    font.italic: true
                }
            }

            // Type
            CardSection {
                title: "camera type"
                Text {
                    width: parent.width
                    text: "How are speed and aperture controlled?"
                    color: FiatLuxTheme.secondaryText
                    font.pixelSize: Theme.fontSizeExtraSmall
                    wrapMode: Text.Wrap
                }
                BackgroundItem {
                    id: typeBtn
                    width: parent.width; height: Theme.itemSizeSmall
                    onClicked: { typeMenu.items = page.typeLabels; typeMenu.show(typeBtn) }
                    Rectangle {
                        anchors.fill: parent; radius: height / 2
                        color: typeBtn.highlighted ? FiatLuxTheme.amberMed : "transparent"
                        border.color: FiatLuxTheme.amber; border.width: 1
                    }
                    Row {
                        anchors.centerIn: parent; spacing: Theme.paddingSmall
                        Text {
                            text: page.typeIndex === -1 ? "tap to choose" : page.typeLabels[page.typeIndex]
                            color: FiatLuxTheme.primaryText
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: FiatLuxTheme.serif; font.italic: true
                        }
                        Text { text: "▾"; color: FiatLuxTheme.amber; font.pixelSize: Theme.fontSizeSmall }
                    }
                }
            }

            // Name + mount
            CardSection {
                title: "camera"
                TextField {
                    id: cameraName
                    width: parent.width
                    placeholderText: "e.g. Pentax MX"
                    label: "Camera name"
                    color: FiatLuxTheme.primaryText
                }
                TextField {
                    id: mountField
                    width: parent.width
                    placeholderText: "e.g. M42, K-mount, Yashica TLR"
                    label: "Lens mount"
                    color: FiatLuxTheme.primaryText
                }
                Flow {
                    visible: knownMounts.length > 0
                    width: parent.width
                    spacing: Theme.paddingSmall
                    Repeater {
                        model: knownMounts
                        delegate: BackgroundItem {
                            width: mtag.width + Theme.paddingMedium * 2
                            height: mtag.height + Theme.paddingSmall * 1.5
                            onClicked: mountField.text = modelData
                            Rectangle {
                                anchors.fill: parent; radius: height / 2
                                color: "transparent"
                                border.color: FiatLuxTheme.rim; border.width: 1
                            }
                            Text {
                                id: mtag; anchors.centerIn: parent; text: modelData
                                color: FiatLuxTheme.secondaryText
                                font.pixelSize: Theme.fontSizeExtraSmall
                            }
                        }
                    }
                }
            }

            // Body speeds (SLR only)
            CardSection {
                visible: typeIndex === 1
                title: "body shutter speeds"
                Flow {
                    width: parent.width; spacing: Theme.paddingSmall
                    Repeater {
                        model: (speedGen, allSpeeds.slice())
                        delegate: Loader {
                            sourceComponent: pillComponent
                            onLoaded: {
                                item.label = modelData
                                item.selected = isSpeedSelected(modelData)
                                item.onToggle = function(sel) {
                                    if (sel) bodySpeeds.push(modelData)
                                    else bodySpeeds = bodySpeeds.filter(function(s){ return s !== modelData })
                                }
                            }
                        }
                    }
                }
                Text {
                    width: parent.width
                    text: "Apertures live on the lens. Add lenses from the Lenses page."
                    color: FiatLuxTheme.secondaryText
                    font.pixelSize: Theme.fontSizeExtraSmall
                    wrapMode: Text.Wrap
                }
            }

            // Hint for non-SLR types
            Text {
                visible: typeIndex === 0 || typeIndex === 2
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: typeIndex === 0
                      ? "This camera's built-in lens carries its own apertures and speeds. Create it on the Lenses page with the same mount."
                      : "Leaf-shutter lenses carry both apertures and speeds. Add them on the Lenses page with the same mount."
                color: FiatLuxTheme.secondaryText
                font.pixelSize: Theme.fontSizeExtraSmall
                wrapMode: Text.Wrap
            }

            // Save
            BackgroundItem {
                id: saveBtn
                width: parent.width; height: Theme.itemSizeLarge
                enabled: page.canSave
                opacity: enabled ? 1.0 : 0.35
                onClicked: {
                    var speeds = (typeIndex === 1) ? bodySpeeds.join(",") : ""
                    if (editId >= 0)
                        Storage.updateCamera(editId, cameraName.text, typeIndex, mountField.text, speeds)
                    else
                        Storage.addCamera(cameraName.text, typeIndex, mountField.text, speeds)
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
                        text: editId >= 0 ? "save changes" : "save camera"
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
        id: typeMenu
        onPicked: function(idx) { page.typeIndex = idx }
    }
}
