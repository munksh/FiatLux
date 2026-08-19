import QtQuick 2.0
import Sailfish.Silica 1.0
import "../Storage.js" as Storage
import ".." 1.0
import "../components"

Page {
    id: page
    allowedOrientations: Orientation.Portrait

    background: Rectangle { color: FiatLuxTheme.deepBg }

    property int rollId: -1

    property ListModel shotModel: ListModel {}

    function reload() { Storage.loadShots(shotModel, rollId) }

    Component.onCompleted: reload()
    onStatusChanged: if (status === PageStatus.Active) reload()

    SilicaListView {
        anchors.fill: parent
        model: page.shotModel
        spacing: Theme.paddingMedium

        header: Item {
            width: page.width; height: Theme.itemSizeLarge
            Text {
                anchors.centerIn: parent; text: "shots"
                color: FiatLuxTheme.primaryText
                font.pixelSize: Theme.fontSizeMedium
                font.family: FiatLuxTheme.serif; font.italic: true
            }
        }

        ViewPlaceholder {
            enabled: page.shotModel.count === 0
            text: "No shots logged yet"
        }

        delegate: ListItem {
            id: item
            width: ListView.view.width
            contentHeight: card.height + Theme.paddingSmall * 2

            menu: ContextMenu {
                backgroundColor: FiatLuxTheme.surface
                highlightColor: FiatLuxTheme.amber
                MenuItem {
                    text: "Delete"
                    color: FiatLuxTheme.warning
                    onClicked: item.remorseAction("Deleting frame " + model.frame, function() {
                        Storage.deleteShot(model.id)
                        page.reload()
                    })
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
                    spacing: Theme.paddingLarge

                    // Frame number
                    Rectangle {
                        width: Theme.itemSizeSmall; height: Theme.itemSizeSmall
                        radius: width / 2
                        color: FiatLuxTheme.amberSoft
                        border.color: FiatLuxTheme.amber; border.width: 1
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            anchors.centerIn: parent
                            text: model.frame
                            color: FiatLuxTheme.amber
                            font.pixelSize: Theme.fontSizeMedium
                            font.family: FiatLuxTheme.mono
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - Theme.itemSizeSmall - Theme.paddingLarge
                        spacing: Theme.paddingSmall

                        Text {
                            text: "f/" + model.aperture + "   " + model.shutterSpeed
                            color: FiatLuxTheme.primaryText
                            font.pixelSize: Theme.fontSizeLarge
                            font.family: FiatLuxTheme.mono
                        }
                        Text {
                            text: "ISO " + model.iso + "   ·   EV " + model.ev.toFixed(1)
                                  + (model.photoPath !== "" ? "   ·   photo" : "")
                            color: FiatLuxTheme.secondaryText
                            font.pixelSize: Theme.fontSizeExtraSmall
                            font.family: FiatLuxTheme.mono
                        }
                    }
                }
            }
        }
    }
}
