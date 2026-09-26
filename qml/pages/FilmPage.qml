import QtQuick 2.0
import Sailfish.Silica 1.0
import "../Storage.js" as Storage
import ".." 1.0
import "../components"

// The films you have added or loaded, one plain row each, box speed to the
// right.

Page {
    id: page
    allowedOrientations: Orientation.Portrait

    function paint() { FiatLuxTheme.applyPalette(page) }
    Component.onCompleted: paint()
    Connections {
        target: FiatLuxTheme
        onAmbientChanged: page.paint()
    }

    PaperBackground { }

    SilicaListView {
        anchors.fill: parent
        model: app.stockModel

        PullDownMenu {
            highlightColor: FiatLuxTheme.accent
            MenuItem {
                text: qsTr("Load film"); color: FiatLuxTheme.primaryText
                onClicked: pageStack.push(Qt.resolvedUrl("AddRollPage.qml"))
            }
            MenuItem {
                text: qsTr("Lenses"); color: FiatLuxTheme.primaryText
                onClicked: pageStack.push(Qt.resolvedUrl("LensesPage.qml"))
            }
            MenuItem {
                text: qsTr("Cameras"); color: FiatLuxTheme.primaryText
                onClicked: pageStack.push(Qt.resolvedUrl("CamerasPage.qml"))
            }
            MenuItem {
                text: qsTr("Add film"); color: FiatLuxTheme.primaryText
                onClicked: pageStack.push(Qt.resolvedUrl("AddStockPage.qml"))
            }
        }

        header: PageHead {
            title: qsTr("film stocks")
            subtitle: "fiat lux"
        }

        ViewPlaceholder {
            enabled: app.stockModel.count === 0
            text: qsTr("No films yet")
            hintText: qsTr("Films you load appear here. Pull down to add one by hand.")
        }

        delegate: ListItem {
            id: item
            width: ListView.view.width
            contentHeight: Theme.itemSizeMedium
            highlightedColor: FiatLuxTheme.highlightWash
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

            Label {
                anchors.left: parent.left
                anchors.leftMargin: Theme.horizontalPageMargin
                anchors.right: isoLabel.left
                anchors.rightMargin: Theme.paddingLarge
                anchors.verticalCenter: parent.verticalCenter
                truncationMode: TruncationMode.Fade
                text: model.name
                color: FiatLuxTheme.primaryText
                font.pixelSize: Theme.fontSizeLarge
                font.family: FiatLuxTheme.serif
                font.italic: true
            }
            Label {
                id: isoLabel
                anchors.right: parent.right
                anchors.rightMargin: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                text: "ISO " + model.boxIso
                color: FiatLuxTheme.secondaryText
                font.pixelSize: Theme.fontSizeSmall
            }
        }

        VerticalScrollDecorator { }
    }
}
