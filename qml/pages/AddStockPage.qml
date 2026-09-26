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

    property int editId: -1

    property bool canSave: stockName.text.length > 0 && isoField.text.length > 0

    Component.onCompleted: {
        if (editId >= 0) {
            var s = Storage.getStock(editId)
            if (s) {
                stockName.text = s.name
                isoField.text = s.boxIso.toString()
            }
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: page.width
            spacing: Theme.paddingLarge

            PageHead {
                title: editId >= 0 ? "edit film stock" : "add film stock"
                subtitle: "fiat lux"
            }

            CardSection {
                title: "film stock"
                TextField {
                    id: stockName
                    width: parent.width
                    placeholderText: "e.g. Ilford HP5 Plus"
                    label: "Stock name"
                    color: FiatLuxTheme.primaryText
                }
                TextField {
                    id: isoField
                    width: parent.width
                    placeholderText: "e.g. 400"
                    label: "Box ISO"
                    color: FiatLuxTheme.primaryText
                    inputMethodHints: Qt.ImhDigitsOnly
                    maximumLength: 5
                    validator: IntValidator { bottom: 1; top: 99999 }
                }
                Text {
                    width: parent.width
                    text: "Box speed only. You set push/pull per roll when you load it."
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
                    if (editId >= 0)
                        Storage.updateStock(editId, stockName.text, parseInt(isoField.text))
                    else
                        Storage.addStock(stockName.text, parseInt(isoField.text))
                    app.reloadStocks()
                    pageStack.pop()
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    height: Theme.itemSizeMedium; radius: Theme.paddingLarge
                    color: saveBtn.highlighted ? FiatLuxTheme.amberStrong : FiatLuxTheme.amber
                    Text {
                        anchors.centerIn: parent
                        text: editId >= 0 ? "save changes" : "save film stock"
                        color: FiatLuxTheme.onAccent
                        font.pixelSize: Theme.fontSizeMedium
                        font.family: FiatLuxTheme.serif; font.italic: true; font.bold: true
                    }
                }
            }

            Item { width: 1; height: Theme.paddingLarge }
        }
    }
}
