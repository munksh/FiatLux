import QtQuick 2.0
import Sailfish.Silica 1.0
import "../Storage.js" as Storage
import ".." 1.0
import "../components"

// A film that is not in the list: its name and its box speed. Push and pull
// are chosen per roll, when it is loaded.

Page {
    id: page
    allowedOrientations: Orientation.Portrait

    property int editId: -1

    readonly property bool canSave: stockName.text.trim().length > 0 && parseInt(isoField.text) > 0

    function paint() { FiatLuxTheme.applyPalette(page) }
    Connections {
        target: FiatLuxTheme
        onAmbientChanged: page.paint()
    }

    Component.onCompleted: {
        paint()
        if (editId >= 0) {
            var s = Storage.getStock(editId)
            if (s) {
                stockName.text = s.name
                isoField.text = s.boxIso.toString()
            }
        }
    }

    function save() {
        var name = stockName.text.trim()
        var iso = parseInt(isoField.text)
        if (page.editId >= 0)
            Storage.updateStock(page.editId, name, iso)
        else
            Storage.addStock(name, iso)
        app.reloadStocks()
        pageStack.pop()
    }

    PaperBackground { }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: page.width

            PageHead {
                title: page.editId >= 0 ? qsTr("edit film") : qsTr("add film")
                subtitle: "fiat lux"
            }

            TextField {
                id: stockName
                width: parent.width
                label: qsTr("Film name")
                placeholderText: qsTr("e.g. Ilford HP5 Plus")
                color: FiatLuxTheme.primaryText
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: isoField.focus = true
            }

            TextField {
                id: isoField
                width: parent.width
                label: qsTr("Box speed, ISO")
                placeholderText: qsTr("e.g. 400")
                color: FiatLuxTheme.primaryText
                inputMethodHints: Qt.ImhDigitsOnly
                maximumLength: 5
                validator: IntValidator { bottom: 1; top: 99999 }
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }

            FormNote {
                text: qsTr("The speed printed on the box. Push and pull are chosen for each roll when you load it.")
            }

            Item { width: 1; height: Theme.paddingLarge * 2 }

            FiatButton {
                text: page.editId >= 0 ? qsTr("save changes") : qsTr("save film")
                enabled: page.canSave
                onClicked: page.save()
            }

            Item { width: 1; height: Theme.paddingLarge }
        }

        VerticalScrollDecorator { }
    }
}
