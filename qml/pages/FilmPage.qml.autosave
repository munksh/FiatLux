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
        model: app.stockModel
        spacing: Theme.paddingMedium

        PullDownMenu {
            backgroundColor: FiatLuxTheme.surface
            highlightColor: FiatLuxTheme.amber
            MenuItem {
                text: "New roll"; color: FiatLuxTheme.primaryText
                onClicked: pageStack.push(Qt.resolvedUrl("AddRollPage.qml"))
            }
            MenuItem {
                text: "Lenses"; color: FiatLuxTheme.primaryText
                onClicked: pageStack.push(Qt.resolvedUrl("LensesPage.qml"))
            }
            MenuItem {
                text: "Cameras"; color: FiatLuxTheme.primaryText
                onClicked: pageStack.push(Qt.resolvedUrl("CamerasPage.qml"))
            }
            MenuItem {
                text: "Add film stock"; color: FiatLuxTheme.primaryText
                onClicked: pageStack.push(Qt.resolvedUrl("AddStockPage.qml"))
            }
        }

        header: Item {
            width: page.width; height: Theme.itemSizeLarge
            Text {
                anchors.centerIn: parent; text: "film stocks"
                color: FiatLuxTheme.primaryText
                font.pixelSize: Theme.fontSizeMedium
                font.family: FiatLuxTheme.serif; font.italic: true
            }
        }

        ViewPlaceholder {
            enabled: app.stockModel.count === 0
            text: "Pull down to add a film stock"
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
                height: row.height + Theme.paddingLarge * 2
                radius: Theme.paddingLarge * 1.5
                color: item.highlighted ? FiatLuxTheme.surface : FiatLuxTheme.deepBg
                border.color: item.highlighted ? FiatLuxTheme.amber : FiatLuxTheme.rim
                border.width: item.highlighted ? 2 : 1

                Row {
                    id: row
                    x: Theme.paddingLarge
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 2 * Theme.paddingLarge

                    Text {
                        text: model.name
                        color: FiatLuxTheme.primaryText
                        font.pixelSize: Theme.fontSizeLarge
                        font.family: FiatLuxTheme.serif; font.italic: true
                        width: parent.width - isoTag.width
                        elide: Text.ElideRight
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Rectangle {
                        id: isoTag
                        radius: height / 2; color: FiatLuxTheme.amberSoft
                        border.color: FiatLuxTheme.amber; border.width: 1
                        width: isoL.width + Theme.paddingMedium * 2
                        height: isoL.height + Theme.paddingSmall * 1.5
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            id: isoL; anchors.centerIn: parent
                            text: "ISO " + model.boxIso; color: FiatLuxTheme.amber
                            font.pixelSize: Theme.fontSizeExtraSmall
                            font.family: FiatLuxTheme.mono
                        }
                    }
                }
            }
        }
    }

    PillMenu {
        id: itemMenu
        onPicked: function(idx) {
            if (idx === 0) pageStack.push(Qt.resolvedUrl("AddStockPage.qml"), { editId: page.activeItemId })
            else if (idx === 1) {
                Storage.deleteStock(page.activeItemId)
                app.reloadStocks()
            }
        }
    }
}
