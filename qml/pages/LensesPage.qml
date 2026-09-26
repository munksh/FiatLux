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

    property int activeItemId: -1

    SilicaListView {
        anchors.fill: parent
        model: app.lensModel
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
                text: "Cameras"; color: FiatLuxTheme.primaryText
                onClicked: pageStack.push(Qt.resolvedUrl("CamerasPage.qml"))
            }
            MenuItem {
                text: "Add lens"; color: FiatLuxTheme.primaryText
                onClicked: pageStack.push(Qt.resolvedUrl("AddLensPage.qml"))
            }
        }

        header: PageHead {
            title: "lenses"
            subtitle: "fiat lux"
        }

        ViewPlaceholder {
            enabled: app.lensModel.count === 0
            text: "Pull down to add a lens"
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
                    text: qsTr("Edit")
                    color: FiatLuxTheme.primaryText
                    onClicked: pageStack.push(Qt.resolvedUrl("AddLensPage.qml"), { editId: item.itemId })
                }
                MenuItem {
                    text: qsTr("Delete")
                    color: FiatLuxTheme.primaryText
                    onClicked: {
                        var id = item.itemId
                        item.remorseAction(qsTr("Deleting"), function() {
                            Storage.deleteLens(id)
                            app.reloadLenses()
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
                    Text {
                        width: parent.width
                        text: "f/" + (model.apertures || "").split(",").join("  f/")
                        color: FiatLuxTheme.secondaryText
                        font.pixelSize: Theme.fontSizeExtraSmall
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

}
