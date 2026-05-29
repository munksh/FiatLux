import QtQuick 2.0
import Sailfish.Silica 1.0
import "../Storage.js" as Storage

Page {
    id: page
    allowedOrientations: Orientation.Portrait

    // Theme-aware solid card colors — appen står på egna ben
    property bool darkTheme: Theme.colorScheme === Theme.LightOnDark
    property color cardColor: darkTheme
        ? Qt.rgba(0.08, 0.08, 0.08, 1.0)
        : Qt.rgba(0.96, 0.96, 0.96, 1.0)
    property color cardColorHighlighted: darkTheme
        ? Qt.rgba(0.16, 0.16, 0.16, 1.0)
        : Qt.rgba(0.88, 0.88, 0.88, 1.0)
    property color cardBorder: Theme.rgba(Theme.primaryColor, 0.45)

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: app.cameraModel
        spacing: Theme.paddingMedium

        PullDownMenu {
            MenuItem {
                text: "Add Camera"
                onClicked: pageStack.animatorPush(Qt.resolvedUrl("AddCameraPage.qml"))
            }
        }

        header: Column {
            width: listView.width
            spacing: Theme.paddingLarge

            // Wordmark
            Item {
                width: parent.width
                height: Theme.itemSizeExtraLarge

                Label {
                    anchors.centerIn: parent
                    text: "FIAT LUX"
                    color: Theme.primaryColor
                    font.pixelSize: Theme.fontSizeLarge
                    font.letterSpacing: Theme.pixelRatio * 5
                    font.weight: Font.Bold
                }
            }

            // Quick Meter card
            BackgroundItem {
                id: quickMeterItem
                width: parent.width
                height: quickMeterCard.height + Theme.paddingSmall * 2
                onClicked: pageStack.animatorPush(Qt.resolvedUrl("MeterPage.qml"))

                Rectangle {
                    id: quickMeterCard
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    height: quickMeterColumn.height + Theme.paddingLarge * 2
                    radius: Theme.paddingLarge * 1.5
                    color: quickMeterItem.highlighted ? page.cardColorHighlighted : page.cardColor
                    border.color: page.cardBorder
                    border.width: 2

                    Column {
                        id: quickMeterColumn
                        x: Theme.paddingLarge
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 2 * Theme.paddingLarge
                        spacing: Theme.paddingSmall

                        Label {
                            text: "Quick Meter"
                            color: Theme.primaryColor
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.Bold
                        }
                        Label {
                            text: "Mät direkt, ingen profil"
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Bold
                        }
                    }
                }
            }
        }

        ViewPlaceholder {
            enabled: listView.count === 0
            text: "Dra ner för att lägga till en kamera"
        }

        delegate: ListItem {
            id: cameraItem
            width: listView.width
            contentHeight: cameraCard.height + Theme.paddingSmall * 2

            property var lensesArr: {
                try { return JSON.parse(model.lenses) } catch (e) { return [] }
            }

            menu: ContextMenu {
                MenuItem {
                    text: "Delete"
                    onClicked: {
                        Storage.deleteCamera(model.id)
                        Storage.loadCameras(app.cameraModel)
                    }
                }
            }

            onClicked: {
                var firstLens = cameraItem.lensesArr[0] || { name: "", apertures: "", speeds: "" }
                var speeds = model.type === 1
                    ? model.bodySpeeds.split(",")
                    : firstLens.speeds.split(",")
                pageStack.animatorPush(Qt.resolvedUrl("MeterPage.qml"), {
                    "cameraName": model.name,
                    "filmName": model.film,
                    "iso": parseInt(model.iso),
                    "isoLocked": true,
                    "lens": firstLens.name,
                    "apertures": firstLens.apertures.split(","),
                    "shutterSpeeds": speeds
                })
            }

            Rectangle {
                id: cameraCard
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                height: cameraContent.height + Theme.paddingLarge * 2
                radius: Theme.paddingLarge * 1.5
                color: cameraItem.highlighted ? page.cardColorHighlighted : page.cardColor
                border.color: page.cardBorder
                border.width: 2

                Column {
                    id: cameraContent
                    x: Theme.paddingLarge
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 2 * Theme.paddingLarge
                    spacing: Theme.paddingMedium

                    Label {
                        text: model.name
                        color: Theme.primaryColor
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Font.Bold
                        width: parent.width
                        truncationMode: TruncationMode.Fade
                    }

                    Flow {
                        width: parent.width
                        spacing: Theme.paddingSmall

                        // ISO pill
                        Rectangle {
                            radius: height / 2
                            color: Theme.rgba(Theme.primaryColor, 0.15)
                            border.color: Theme.rgba(Theme.primaryColor, 0.55)
                            border.width: 1
                            width: isoLabel.width + Theme.paddingMedium * 2
                            height: isoLabel.height + Theme.paddingSmall * 1.5
                            Label {
                                id: isoLabel
                                anchors.centerIn: parent
                                text: "ISO " + model.iso
                                color: Theme.primaryColor
                                font.pixelSize: Theme.fontSizeExtraSmall
                                font.weight: Font.Bold
                            }
                        }

                        // Film pill
                        Rectangle {
                            visible: model.film && model.film.length > 0
                            radius: height / 2
                            color: Theme.rgba(Theme.primaryColor, 0.15)
                            border.color: Theme.rgba(Theme.primaryColor, 0.55)
                            border.width: 1
                            width: filmLabel.width + Theme.paddingMedium * 2
                            height: filmLabel.height + Theme.paddingSmall * 1.5
                            Label {
                                id: filmLabel
                                anchors.centerIn: parent
                                text: model.film
                                color: Theme.primaryColor
                                font.pixelSize: Theme.fontSizeExtraSmall
                                font.weight: Font.Bold
                            }
                        }

                        // Lens pills
                        Repeater {
                            model: cameraItem.lensesArr
                            delegate: Rectangle {
                                radius: height / 2
                                color: Theme.rgba(Theme.primaryColor, 0.15)
                                border.color: Theme.rgba(Theme.primaryColor, 0.55)
                                border.width: 1
                                width: lensLabel.width + Theme.paddingMedium * 2
                                height: lensLabel.height + Theme.paddingSmall * 1.5
                                Label {
                                    id: lensLabel
                                    anchors.centerIn: parent
                                    text: modelData.name
                                    color: Theme.primaryColor
                                    font.pixelSize: Theme.fontSizeExtraSmall
                                    font.weight: Font.Bold
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
