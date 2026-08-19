import QtQuick 2.0
import Sailfish.Silica 1.0
import "../Storage.js" as Storage
import ".." 1.0
import "../components"

Page {
    id: page
    allowedOrientations: Orientation.Portrait
    background: Rectangle { color: FiatLuxTheme.deepBg }

    property var typeLabels: ["Fixed", "SLR / RF", "Leaf"]
    property int activeItemId: -1

    SilicaListView {
        anchors.fill: parent
        model: app.cameraModel
        spacing: Theme.paddingMedium

        PullDownMenu {
            backgroundColor: FiatLuxTheme.surface
            highlightColor: FiatLuxTheme.amber
            MenuItem {
                text: "New roll"; color: FiatLuxTheme.primaryText
                onClicked: pageStack.push(Qt.resolvedUrl("AddRollPage.qml"))
            }
            MenuItem {
                text: "Film stocks"; color: FiatLuxTheme.primaryText
                onClicked: pageStack.push(Qt.resolvedUrl("FilmPage.qml"))
            }
            MenuItem {
                text: "Lenses"; color: FiatLuxTheme.primaryText
                onClicked: pageStack.push(Qt.resolvedUrl("LensesPage.qml"))
            }
            MenuItem {
                text: "Add camera"; color: FiatLuxTheme.primaryText
                onClicked: pageStack.push(Qt.resolvedUrl("AddCameraPage.qml"))
            }
        }

        header: Item {
            width: page.width; height: Theme.itemSizeLarge
            Text {
                anchors.centerIn: parent; text: "cameras"
                color: FiatLuxTheme.primaryText
                font.pixelSize: Theme.fontSizeMedium
                font.family: FiatLuxTheme.serif; font.italic: true
            }
        }

        ViewPlaceholder {
            enabled: app.cameraModel.count === 0
            text: "Pull down to add a camera"
        }

        delegate: BackgroundItem {
            id: item
            width: ListView.view.width
            height: card.height + Theme.paddingSmall * 2
            onClicked: {
                page.activeItemId = model.id
                itemMenu.items = ["Meter with this camera", "Edit", "Delete"]
                itemMenu.show(item)
            }

            Rectangle {
                id: card
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                height: col.height + Theme.paddingLarge * 2
                radius: Theme.paddingLarge * 1.5
                color: item.highlighted ? FiatLuxTheme.surface : FiatLuxTheme.deepBg
                border.color: item.highlighted ? FiatLuxTheme.amber : FiatLuxTheme.rim
                border.width: item.highlighted ? 2 : 1

                Column {
                    id: col
                    x: Theme.paddingLarge
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 2 * Theme.paddingLarge
                    spacing: Theme.paddingSmall

                    Text {
                        text: model.name
                        color: FiatLuxTheme.primaryText
                        font.pixelSize: Theme.fontSizeLarge
                        font.family: FiatLuxTheme.serif; font.italic: true
                        width: parent.width; elide: Text.ElideRight
                    }
                    Row {
                        spacing: Theme.paddingSmall
                        Rectangle {
                            radius: height / 2; color: "transparent"
                            border.color: FiatLuxTheme.rim; border.width: 1
                            width: typeL.width + Theme.paddingMedium * 2
                            height: typeL.height + Theme.paddingSmall * 1.5
                            Text {
                                id: typeL; anchors.centerIn: parent
                                text: page.typeLabels[model.type]
                                color: FiatLuxTheme.secondaryText
                                font.pixelSize: Theme.fontSizeExtraSmall
                            }
                        }
                        Rectangle {
                            radius: height / 2; color: FiatLuxTheme.amberSoft
                            border.color: FiatLuxTheme.amber; border.width: 1
                            width: mountL.width + Theme.paddingMedium * 2
                            height: mountL.height + Theme.paddingSmall * 1.5
                            Text {
                                id: mountL; anchors.centerIn: parent
                                text: model.mount; color: FiatLuxTheme.amber
                                font.pixelSize: Theme.fontSizeExtraSmall
                                font.family: FiatLuxTheme.mono
                            }
                        }
                    }
                }
            }
        }
    }

    PillMenu {
        id: itemMenu
        onPicked: function(idx) {
            if (idx === 0) pageStack.push(Qt.resolvedUrl("MeterPage.qml"), { presetCameraId: page.activeItemId })
            else if (idx === 1) pageStack.push(Qt.resolvedUrl("AddCameraPage.qml"), { editId: page.activeItemId })
            else if (idx === 2) {
                Storage.deleteCamera(page.activeItemId)
                app.reloadCameras()
            }
        }
    }
}
