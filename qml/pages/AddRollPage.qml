import QtQuick 2.0
import Sailfish.Silica 1.0
import "../Storage.js" as Storage
import ".." 1.0

Page {
    id: page
    allowedOrientations: Orientation.Portrait

    background: Rectangle { color: FiatLuxTheme.deepBg }

    property int editId: -1
    // Set true when pushed from MeterPage pull-down so Save returns to meter
    // with the new roll active instead of just popping.
    property bool returnToMeter: false

    property int stockId: -1
    property int cameraId: -1
    property int lensId: -1
    property string cameraMount: ""
    property var compatLenses: []

    property string stockLabel: "tap to choose"
    property string cameraLabel: "tap to choose"
    property string lensLabel: "tap to choose"

    property bool canSave: stockId >= 0 && pushIso.text.length > 0

    Component.onCompleted: {
        if (editId >= 0) {
            var r = Storage.getRoll(editId)
            if (r) {
                stockId = r.stockId; stockLabel = r.stockName
                pushIso.text = r.pushIso.toString()
                if (r.cameraId) { cameraId = r.cameraId; cameraLabel = r.cameraName; cameraMount = r.mount; refreshLenses() }
                if (r.lensId)   { lensId = r.lensId; lensLabel = r.lensName }
            }
        }
    }

    function refreshLenses() {
        compatLenses = cameraMount.length > 0 ? Storage.lensesForMount(cameraMount) : []
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: page.width
            spacing: Theme.paddingLarge

            Item {
                width: parent.width; height: Theme.itemSizeLarge
                Text {
                    anchors.centerIn: parent
                    text: editId >= 0 ? "edit roll" : "new roll"
                    color: FiatLuxTheme.primaryText
                    font.pixelSize: Theme.fontSizeLarge
                    font.family: FiatLuxTheme.serif; font.italic: true
                }
            }

            CardSection {
                title: "film"
                ChooserRow {
                    label: page.stockLabel
                    onTapped: {
                        var arr = []
                        for (var i = 0; i < app.stockModel.count; i++)
                            arr.push(app.stockModel.get(i).name + "  ISO " + app.stockModel.get(i).boxIso)
                        arr.push("+ new film stock…")
                        stockMenu.items = arr
                        stockMenu.show(anchor)
                    }
                }
                Row {
                    width: parent.width; spacing: Theme.paddingMedium
                    Text {
                        text: "shoot at"
                        color: FiatLuxTheme.secondaryText
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: FiatLuxTheme.serif; font.italic: true
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    TextField {
                        id: pushIso
                        width: Theme.itemSizeHuge
                        placeholderText: "ISO"
                        label: "Rated ISO (push/pull)"
                        color: FiatLuxTheme.primaryText
                        inputMethodHints: Qt.ImhDigitsOnly
                        maximumLength: 5
                        validator: IntValidator { bottom: 1; top: 99999 }
                    }
                }
            }

            CardSection {
                title: "camera"
                ChooserRow {
                    label: page.cameraLabel
                    onTapped: {
                        var arr = []
                        for (var i = 0; i < app.cameraModel.count; i++)
                            arr.push(app.cameraModel.get(i).name)
                        cameraMenu.items = arr
                        cameraMenu.show(anchor)
                    }
                }
            }

            CardSection {
                visible: cameraId >= 0
                title: "lens"
                ChooserRow {
                    label: page.lensLabel
                    enabled: page.compatLenses.length > 0
                    onTapped: {
                        if (page.compatLenses.length === 0) return
                        var arr = []
                        for (var i = 0; i < page.compatLenses.length; i++)
                            arr.push(page.compatLenses[i].name)
                        lensMenu.items = arr
                        lensMenu.show(anchor)
                    }
                }
                Text {
                    visible: page.compatLenses.length === 0
                    width: parent.width
                    text: "No lenses with mount \"" + cameraMount + "\". Add one from Lenses."
                    color: FiatLuxTheme.secondaryText
                    font.pixelSize: Theme.fontSizeExtraSmall
                    wrapMode: Text.Wrap
                }
            }

            BackgroundItem {
                id: saveBtn
                width: parent.width; height: Theme.itemSizeLarge
                enabled: page.canSave
                opacity: enabled ? 1.0 : 0.35
                onClicked: {
                    var newId
                    if (editId >= 0) {
                        Storage.updateRoll(editId, stockId, parseInt(pushIso.text), cameraId, lensId, "")
                        newId = editId
                    } else {
                        newId = Storage.addRoll(stockId, parseInt(pushIso.text), cameraId, lensId,
                                                new Date().toISOString(), "")
                    }
                    app.reloadRolls()

                    if (returnToMeter) {
                        // Pop back to MeterPage and activate this roll
                        pageStack.pop()
                        pageStack.currentPage.loadRoll(newId)
                    } else {
                        pageStack.pop()
                    }
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    height: Theme.itemSizeMedium; radius: Theme.paddingLarge
                    color: saveBtn.highlighted ? FiatLuxTheme.amberStrong : FiatLuxTheme.amber
                    Text {
                        anchors.centerIn: parent
                        text: editId >= 0 ? "save changes" : "load roll"
                        color: FiatLuxTheme.deepBg
                        font.pixelSize: Theme.fontSizeMedium
                        font.family: FiatLuxTheme.serif; font.italic: true; font.bold: true
                    }
                }
            }

            Item { width: 1; height: Theme.paddingLarge }
        }
    }

    PillMenu {
        id: stockMenu
        onPicked: function(idx) {
            if (idx === app.stockModel.count) {
                pageStack.push(Qt.resolvedUrl("AddStockPage.qml"))
                return
            }
            var s = app.stockModel.get(idx)
            page.stockId = s.id; page.stockLabel = s.name
            if (pushIso.text.length === 0) pushIso.text = s.boxIso.toString()
        }
    }

    PillMenu {
        id: cameraMenu
        onPicked: function(idx) {
            var c = app.cameraModel.get(idx)
            page.cameraId = c.id; page.cameraLabel = c.name
            page.cameraMount = c.mount
            page.lensId = -1; page.lensLabel = "tap to choose"
            page.refreshLenses()
            if (page.compatLenses.length === 1) {
                page.lensId = page.compatLenses[0].id
                page.lensLabel = page.compatLenses[0].name
            }
        }
    }

    PillMenu {
        id: lensMenu
        onPicked: function(idx) {
            page.lensId = page.compatLenses[idx].id
            page.lensLabel = page.compatLenses[idx].name
        }
    }
}
