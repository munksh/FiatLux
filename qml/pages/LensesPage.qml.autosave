import QtQuick 2.0
import Sailfish.Silica 1.0
import "../Storage.js" as Storage
import ".." 1.0
import "../components"

Page {
    id: page
    allowedOrientations: Orientation.Portrait
    background: Rectangle { color: FiatLuxTheme.deepBg }

    property int activeItemId: -1

    SilicaListView {
        anchors.fill: parent
        model: app.lensModel
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
                text: "Cameras"; color: FiatLuxTheme.primaryText
                onClicked: pageStack.push(Qt.resolvedUrl("CamerasPage.qml"))
            }
            MenuItem {
                text: "Add lens"; color: FiatLuxTheme.primaryText
                onClicked: pageStack.push(Qt.resolvedUrl("AddLensPage.qml"))
            }
        }

        header: Item {
            width: page.width; height: Theme.itemSizeLarge
            Text {
                anchors.centerIn: parent; text: "lenses"
                color: FiatLuxTheme.primaryText
                font.pixelSize: Theme.fontSizeMedium
                font.family: FiatLuxTheme.serif; font.italic: true
            }
        }

        ViewPlaceholder {
            enabled: app.lensModel.count === 0
            text: "Pull down to add a lens"
        }

        delegate: BackgroundItem {
            id: item
            width: ListView.view.width
            height: card.height + Theme.paddingSmall * 2
            onClicked: {
                page.activeItemId = model.id
                itemMenu.items = ["Edit", "Delete"]
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

    PillMenu {
        id: itemMenu
        onPicked: function(idx) {
            if (idx === 0) pageStack.push(Qt.resolvedUrl("AddLensPage.qml"), { editId: page.activeItemId })
            else if (idx === 1) {
                Storage.deleteLens(page.activeItemId)
                app.reloadLenses()
            }
        }
    }
}
