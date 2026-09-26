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
        model: app.stockModel
        spacing: Theme.paddingMedium

        PullDownMenu {
            backgroundColor: FiatLuxTheme.surface
            highlightColor: FiatLuxTheme.amber
            MenuItem {
                text: "Load film"; color: FiatLuxTheme.primaryText
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

        header: PageHead {
            title: "film stocks"
            subtitle: "fiat lux"
        }

        ViewPlaceholder {
            enabled: app.stockModel.count === 0
            text: "Pull down to add a film stock"
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
                    onClicked: pageStack.push(Qt.resolvedUrl("AddStockPage.qml"), { editId: item.itemId })
                }
                MenuItem {
                    text: qsTr("Delete")
                    color: FiatLuxTheme.primaryText
                    onClicked: {
                        var id = item.itemId
                        item.remorseAction(qsTr("Deleting"), function() {
                            Storage.deleteStock(id)
                            app.reloadStocks()
                        })
                    }
                }
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

}
