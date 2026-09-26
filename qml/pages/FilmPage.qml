import QtQuick 2.0
import Sailfish.Silica 1.0
import "../Storage.js" as Storage
import ".." 1.0
import "../components"

// The film that is in your cameras right now: one row per loaded roll. Films
// are added where they are used, on Load film; this page is for seeing what
// is loaded, going to the meter with it, and taking it out.

Page {
    id: page
    allowedOrientations: Orientation.Portrait

    function paint() { FiatLuxTheme.applyPalette(page) }
    Component.onCompleted: paint()
    Connections {
        target: FiatLuxTheme
        onAmbientChanged: page.paint()
    }

    onStatusChanged: if (status === PageStatus.Active) app.reloadRolls()

    function since(iso) {
        var d = new Date(iso)
        if (isNaN(d.getTime())) return ""
        return qsTr("since %1").arg(Qt.formatDate(d, "d MMM"))
    }

    function describe(r) {
        var parts = [r.cameraName !== "" ? r.cameraName : qsTr("no camera"), "ISO " + r.pushIso]
        if (r.lensName !== "") parts.push(r.lensName)
        parts.push(r.shotCount === 1 ? qsTr("1 frame") : qsTr("%1 frames").arg(r.shotCount))
        var s = page.since(r.startDate)
        if (s !== "") parts.push(s)
        return parts.join("  ·  ")
    }

    // Back to the one meter there is, with this roll.
    function meterWith(rollId) {
        var meter = pageStack.find(function(p) { return typeof p.loadRoll === "function" })
        if (meter) {
            pageStack.pop(meter)
            meter.loadRoll(rollId)
        }
    }

    PaperBackground { }

    SilicaListView {
        anchors.fill: parent
        model: app.rollModel

        PullDownMenu {
            highlightColor: FiatLuxTheme.accent
            MenuItem {
                text: qsTr("Lenses"); color: FiatLuxTheme.primaryText
                onClicked: pageStack.push(Qt.resolvedUrl("LensesPage.qml"))
            }
            MenuItem {
                text: qsTr("Cameras"); color: FiatLuxTheme.primaryText
                onClicked: pageStack.push(Qt.resolvedUrl("CamerasPage.qml"))
            }
            MenuItem {
                text: qsTr("Load film"); color: FiatLuxTheme.primaryText
                onClicked: pageStack.push(Qt.resolvedUrl("AddRollPage.qml"))
            }
        }

        header: PageHead {
            title: qsTr("loaded film")
            subtitle: "fiat lux"
        }

        ViewPlaceholder {
            enabled: app.rollModel.count === 0
            text: qsTr("No film loaded")
            hintText: qsTr("Pull down to load a film into a camera")
        }

        delegate: ListItem {
            id: item
            width: ListView.view.width
            contentHeight: col.height + Theme.paddingMedium * 2
            highlightedColor: FiatLuxTheme.highlightWash
            readonly property int rollId: model.id
            readonly property int cameraId: model.cameraId
            onClicked: openMenu()

            // A hairline between rows, as in Mos. None under the last one.
            Rectangle {
                anchors.bottom: parent.bottom
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                height: 1
                color: FiatLuxTheme.innerBorder
                visible: index < app.rollModel.count - 1
            }

            menu: ContextMenu {
                highlightColor: FiatLuxTheme.accent
                MenuItem {
                    text: qsTr("Frames and days")
                    color: FiatLuxTheme.primaryText
                    onClicked: pageStack.push(Qt.resolvedUrl("ShotsPage.qml"), { rollId: item.rollId })
                }
                MenuItem {
                    text: qsTr("Meter with this film")
                    color: FiatLuxTheme.primaryText
                    onClicked: page.meterWith(item.rollId)
                }
                MenuItem {
                    text: qsTr("Load another film")
                    color: FiatLuxTheme.primaryText
                    onClicked: pageStack.push(Qt.resolvedUrl("AddRollPage.qml"), { presetCameraId: item.cameraId })
                }
                MenuItem {
                    text: qsTr("Unload")
                    color: FiatLuxTheme.primaryText
                    onClicked: {
                        var id = item.rollId
                        item.remorseAction(qsTr("Unloading"), function() {
                            Storage.closeRoll(id)
                            app.reloadRolls()
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
                    text: model.stockName
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
