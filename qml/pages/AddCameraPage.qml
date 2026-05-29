import QtQuick 2.0
import Sailfish.Silica 1.0
import "../Storage.js" as Storage

Page {
    id: page
    allowedOrientations: Orientation.Portrait

    property var allApertures: ["1", "1.4", "1.7", "2", "2.8", "4", "5.6", "8", "11", "16", "22"]
    property var allSpeeds: ["1/1000", "1/500", "1/300", "1/250", "1/125", "1/100", "1/60", "1/50", "1/30", "1/15", "1/8", "1/4", "1/2", "1\"", "B"]

    property var bodySpeeds: []
    property var currentLensApertures: []
    property var currentLensSpeeds: []
    property var lenses: []

    // Reusable pill component
    Component {
        id: pillComponent

        Rectangle {
            property bool selected: false
            property string label: ""
            property var onToggle

            width: pillLabel.implicitWidth + Theme.paddingLarge
            height: Theme.itemSizeExtraSmall * 0.7
            radius: height / 2
            color: selected ? Theme.highlightColor : "transparent"
            border.color: selected ? Theme.highlightColor : Theme.primaryColor
            border.width: 1

            Label {
                id: pillLabel
                anchors.centerIn: parent
                text: parent.label
                color: parent.selected ? Theme.highlightDimmerColor : Theme.primaryColor
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
            spacing: Theme.paddingMedium

            PageHeader { title: "Add Camera" }

            SectionHeader { text: "Camera Type" }

            Label {
                x: Theme.horizontalPageMargin
                width: page.width - 2 * Theme.horizontalPageMargin
                text: "How are speed and aperture controlled?"
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.Wrap
            }

            ComboBox {
                id: cameraType
                width: page.width
                label: "Type"
                currentIndex: -1
                description: "Tap to choose"
                menu: ContextMenu {
                    MenuItem { text: "Fixed — built-in lens (Yashica B)" }
                    MenuItem { text: "SLR / Rangefinder — speeds on body (Pentax MX)" }
                    MenuItem { text: "Leaf shutter — everything on lens (Hasselblad)" }
                }
            }

            SectionHeader { text: "Camera" }

            TextField {
                id: cameraName
                width: page.width - 2 * Theme.horizontalPageMargin
                x: Theme.horizontalPageMargin
                placeholderText: "e.g. Pentax MX"
                label: "Camera name"
            }

            SectionHeader { text: "Film" }

            TextField {
                id: filmName
                width: page.width - 2 * Theme.horizontalPageMargin
                x: Theme.horizontalPageMargin
                placeholderText: "e.g. Ilford HP5"
                label: "Film name"
            }

            TextField {
                id: isoField
                width: page.width - 2 * Theme.horizontalPageMargin
                x: Theme.horizontalPageMargin
                placeholderText: "e.g. 400"
                label: "ISO"
                inputMethodHints: Qt.ImhDigitsOnly
                maximumLength: 4
                validator: IntValidator { bottom: 1; top: 9999 }
            }

            // Body shutter speeds — only for SLR type
            SectionHeader {
                text: "Body Shutter Speeds"
                visible: cameraType.currentIndex === 1
            }

            Flow {
                visible: cameraType.currentIndex === 1
                x: Theme.horizontalPageMargin
                width: page.width - 2 * Theme.horizontalPageMargin
                spacing: Theme.paddingSmall

                Repeater {
                    model: allSpeeds
                    delegate: Loader {
                        sourceComponent: pillComponent
                        onLoaded: {
                            item.label = modelData
                            item.onToggle = function(sel) {
                                if (sel) bodySpeeds.push(modelData)
                                else bodySpeeds = bodySpeeds.filter(function(s) { return s !== modelData })
                            }
                        }
                    }
                }
            }

            SectionHeader { text: cameraType.currentIndex === 0 ? "Built-in Lens" : "Lens" }

            TextField {
                id: lensName
                width: page.width - 2 * Theme.horizontalPageMargin
                x: Theme.horizontalPageMargin
                placeholderText: "e.g. SMC Pentax 50mm f/1.7"
                label: "Lens name"
            }

            SectionHeader { text: "Apertures" }

            Flow {
                x: Theme.horizontalPageMargin
                width: page.width - 2 * Theme.horizontalPageMargin
                spacing: Theme.paddingSmall

                Repeater {
                    model: allApertures
                    delegate: Loader {
                        sourceComponent: pillComponent
                        onLoaded: {
                            item.label = "f/" + modelData
                            item.onToggle = function(sel) {
                                if (sel) currentLensApertures.push(modelData)
                                else currentLensApertures = currentLensApertures.filter(function(a) { return a !== modelData })
                            }
                        }
                    }
                }
            }

            // Lens speeds — for Fixed and Leaf types
            SectionHeader {
                text: "Lens Shutter Speeds"
                visible: cameraType.currentIndex !== 1 && cameraType.currentIndex !== -1
            }

            Flow {
                visible: cameraType.currentIndex !== 1 && cameraType.currentIndex !== -1
                x: Theme.horizontalPageMargin
                width: page.width - 2 * Theme.horizontalPageMargin
                spacing: Theme.paddingSmall

                Repeater {
                    model: allSpeeds
                    delegate: Loader {
                        sourceComponent: pillComponent
                        onLoaded: {
                            item.label = modelData
                            item.onToggle = function(sel) {
                                if (sel) currentLensSpeeds.push(modelData)
                                else currentLensSpeeds = currentLensSpeeds.filter(function(s) { return s !== modelData })
                            }
                        }
                    }
                }
            }

            Button {
                visible: cameraType.currentIndex !== 0 && cameraType.currentIndex !== -1
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Add Another Lens"
                onClicked: {
                    lenses.push({
                        "name": lensName.text,
                        "apertures": currentLensApertures.join(","),
                        "speeds": currentLensSpeeds.join(",")
                    })
                    lensName.text = ""
                    currentLensApertures = []
                    currentLensSpeeds = []
                    lensAddedNotice.text = lenses.length + " lens(es) added"
                    lensAddedNotice.visible = true
                }
            }

            Label {
                id: lensAddedNotice
                visible: false
                x: Theme.horizontalPageMargin
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeSmall
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Save Camera"
                onClicked: {
                    if (lensName.text.length > 0 || currentLensApertures.length > 0) {
                        lenses.push({
                            "name": lensName.text,
                            "apertures": currentLensApertures.join(","),
                            "speeds": currentLensSpeeds.join(",")
                        })
                    }

                    Storage.addCamera(
                        cameraName.text,
                        filmName.text,
                        parseInt(isoField.text),
                        cameraType.currentIndex,
                        bodySpeeds.join(","),
                        JSON.stringify(lenses)
                    )

                    Storage.loadCameras(app.cameraModel)
                    pageStack.pop()
                }
            }
        }
    }
}
