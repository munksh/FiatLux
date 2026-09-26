import QtQuick 2.0
import Sailfish.Silica 1.0
import "../Storage.js" as Storage
import ".." 1.0
import "../components"

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

    property var typeLabels: ["built-in lens", "shutter in body", "shutter in lens"]
    property int activeItemId: -1

    SilicaListView {
        anchors.fill: parent
        model: app.cameraModel
        spacing: Theme.paddingMedium

        PullDownMenu {
            backgroundColor: FiatLuxTheme.surface
            highlightColor: FiatLuxTheme.amber
            MenuItem {
                text: "Load film"; color: FiatLuxTheme.primaryText
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

        header: PageHead {
            title: "cameras"
            subtitle: "fiat lux"
        }

        ViewPlaceholder {
            enabled: app.cameraModel.count === 0
            text: "Pull down to add a camera"
        }

        delegate: ListItem {
            id: item
            width: ListView.view.width
            contentHeight: card.height + Theme.paddingSmall * 2
            readonly property int itemId: model.id
            onClicked: openMenu()

            menu: ContextMenu {
                highlightColor: FiatLuxTheme.accent
                MenuItem {
                    text: qsTr("Meter with this camera")
                    color: FiatLuxTheme.primaryText
                    onClicked: pageStack.push(Qt.resolvedUrl("MeterPage.qml"), { presetCameraId: item.itemId })
                }
                MenuItem {
                    text: qsTr("Load film")
                    color: FiatLuxTheme.primaryText
                    onClicked: pageStack.push(Qt.resolvedUrl("AddRollPage.qml"), { presetCameraId: item.itemId })
                }
                MenuItem {
                    text: qsTr("Edit")
                    color: FiatLuxTheme.primaryText
                    onClicked: pageStack.push(Qt.resolvedUrl("AddCameraPage.qml"), { editId: item.itemId })
                }
                MenuItem {
                    text: qsTr("Delete")
                    color: FiatLuxTheme.primaryText
                    onClicked: {
                        var id = item.itemId
                        item.remorseAction(qsTr("Deleting"), function() {
                            Storage.deleteCamera(id)
                            app.reloadCameras()
                        })
                    }
                }
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

}
