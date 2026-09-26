import QtQuick 2.0
import Sailfish.Silica 1.0
import "../Storage.js" as Storage
import "../Gear.js" as Gear
import ".." 1.0
import "../components"

// Your lenses, one plain row each: the name, and under it the mount and the
// apertures (and speeds, for a lens with its own shutter).

Page {
    id: page
    allowedOrientations: Orientation.Portrait

    function paint() { FiatLuxTheme.applyPalette(page) }
    Component.onCompleted: paint()
    Connections {
        target: FiatLuxTheme
        onAmbientChanged: page.paint()
    }

    function describe(l) {
        var parts = [l.mount !== "" ? l.mount : qsTr("no mount")]
        var a = Gear.splitList(l.apertures)
        if (a.length > 0) parts.push(Gear.apertureSummary(a))
        var s = Gear.splitList(l.speeds)
        if (s.length > 0) parts.push(Gear.speedCount(s))
        return parts.join("  ·  ")
    }

    PaperBackground { }

    SilicaListView {
        anchors.fill: parent
        model: app.lensModel

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
                text: qsTr("Cameras"); color: FiatLuxTheme.primaryText
                onClicked: pageStack.push(Qt.resolvedUrl("CamerasPage.qml"))
            }
            MenuItem {
                text: qsTr("Add lens"); color: FiatLuxTheme.primaryText
                onClicked: pageStack.push(Qt.resolvedUrl("AddLensPage.qml"))
            }
        }

        header: PageHead {
            title: qsTr("lenses")
            subtitle: "fiat lux"
        }

        ViewPlaceholder {
            enabled: app.lensModel.count === 0
            text: qsTr("No lenses yet")
            hintText: qsTr("Only for cameras whose lens comes off. Pull down to add one.")
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
                    font.pixelSize: Theme.fontSizeMedium
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
