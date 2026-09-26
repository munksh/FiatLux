import QtQuick 2.0
import Sailfish.Silica 1.0
import "../Storage.js" as Storage
import "../Gear.js" as Gear
import ".." 1.0
import "../components"

// Your cameras, one plain row each: the name, and under it what the meter
// needs to know about it. Tap a row for what you can do with it.

Page {
    id: page
    allowedOrientations: Orientation.Portrait

    function paint() { FiatLuxTheme.applyPalette(page) }
    Component.onCompleted: paint()
    Connections {
        target: FiatLuxTheme
        onAmbientChanged: page.paint()
    }

    function describe(c) {
        var parts = []
        if (c.type === 0) {
            parts.push(qsTr("built-in lens"))
            if (c.apertures) parts.push(Gear.apertureSummary(Gear.splitList(c.apertures)))
        } else {
            parts.push(c.mount !== "" ? c.mount : qsTr("no mount"))
            parts.push(c.type === 1 ? qsTr("shutter in the body") : qsTr("shutter in each lens"))
        }
        if (c.type !== 2 && c.bodySpeeds) parts.push(Gear.speedCount(Gear.splitList(c.bodySpeeds)))
        return parts.join("  ·  ")
    }

    // Back to the one meter there is, rather than stacking a second one on
    // top: two meters would fight over the camera.
    function meterWith(id) {
        var meter = pageStack.find(function(p) { return typeof p.loadCamera === "function" })
        if (meter) {
            pageStack.pop(meter)
            meter.loadCamera(id)
        }
    }

    PaperBackground { }

    SilicaListView {
        anchors.fill: parent
        model: app.cameraModel

        PullDownMenu {
            highlightColor: FiatLuxTheme.accent
            MenuItem {
                text: qsTr("Load film"); color: FiatLuxTheme.primaryText
                onClicked: pageStack.push(Qt.resolvedUrl("AddRollPage.qml"))
            }
            MenuItem {
                text: qsTr("Film stocks"); color: FiatLuxTheme.primaryText
                onClicked: pageStack.push(Qt.resolvedUrl("FilmPage.qml"))
            }
            MenuItem {
                text: qsTr("Lenses"); color: FiatLuxTheme.primaryText
                onClicked: pageStack.push(Qt.resolvedUrl("LensesPage.qml"))
            }
            MenuItem {
                text: qsTr("Add camera"); color: FiatLuxTheme.primaryText
                onClicked: pageStack.push(Qt.resolvedUrl("AddCameraPage.qml"))
            }
        }

        header: PageHead {
            title: qsTr("cameras")
            subtitle: "fiat lux"
        }

        ViewPlaceholder {
            enabled: app.cameraModel.count === 0
            text: qsTr("No cameras yet")
            hintText: qsTr("Pull down to add one")
        }

        delegate: ListItem {
            id: item
            width: ListView.view.width
            contentHeight: col.height + Theme.paddingMedium * 2
            highlightedColor: FiatLuxTheme.highlightWash
            readonly property int itemId: model.id
            onClicked: openMenu()

            menu: ContextMenu {
                highlightColor: FiatLuxTheme.accent
                MenuItem {
                    text: qsTr("Meter with this camera")
                    color: FiatLuxTheme.primaryText
                    onClicked: page.meterWith(item.itemId)
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

            Column {
                id: col
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                anchors.verticalCenter: parent.verticalCenter

                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    text: model.name
                    color: FiatLuxTheme.primaryText
                    font.pixelSize: Theme.fontSizeLarge
                    font.family: FiatLuxTheme.serif
                    font.italic: true
                }
                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    text: page.describe(model)
                    color: FiatLuxTheme.secondaryText
                    font.pixelSize: Theme.fontSizeExtraSmall
                }
            }
        }

        VerticalScrollDecorator { }
    }
}
