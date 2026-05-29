import QtQuick 2.0
import Sailfish.Silica 1.0
import "../Storage.js" as Storage

Page {
    id: page
    allowedOrientations: Orientation.Portrait

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: app.cameraModel

        header: PageHeader { title: "Fiat Lux" }

        PullDownMenu {
            MenuItem {
                text: "Add Camera"
                onClicked: pageStack.animatorPush(Qt.resolvedUrl("AddCameraPage.qml"))
            }
            MenuItem {
                text: "Quick Meter"
                onClicked: pageStack.animatorPush(Qt.resolvedUrl("MeterPage.qml"))
            }
        }

        ViewPlaceholder {
            enabled: listView.count === 0
            text: "Pull down to add your first camera or use Quick Meter"
        }

        delegate: ListItem {
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
                var lensesArr = JSON.parse(model.lenses)
                var firstLens = lensesArr[0] || { name: "", apertures: "", speeds: "" }
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

            Column {
                x: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 2 * Theme.horizontalPageMargin

                Label {
                    text: model.name
                    color: Theme.primaryColor
                    font.pixelSize: Theme.fontSizeMedium
                }

                Label {
                    text: model.film + " · ISO " + model.iso
                    color: Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                }
            }
        }
    }
}
