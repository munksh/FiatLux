import QtQuick 2.0
import Sailfish.Silica 1.0
import "../Storage.js" as Storage
import ".." 1.0

Page {
    id: page
    allowedOrientations: Orientation.Portrait

    background: Rectangle { color: FiatLuxTheme.deepBg }

    property int editId: -1
    // Optional: pre-fill mount when launched from a camera context
    property string presetMount: ""

    property var allApertures: ["1","1.4","1.7","2","2.8","4","5.6","8","11","16","22"]
    property var allSpeeds: ["1/1000","1/500","1/300","1/250","1/125","1/100","1/60","1/50","1/30","1/15","1/8","1/4","1/2","1\"","B"]
    property var selApertures: []
    property var selSpeeds: []
    property var knownMounts: []
    property int gen: 0

    property bool canSave: lensName.text.length > 0 && mountField.text.length > 0 && selApertures.length > 0

    Component.onCompleted: {
        knownMounts = Storage.mounts()
        if (presetMount.length > 0) mountField.text = presetMount
        if (editId >= 0) {
            var l = Storage.getLens(editId)
            if (l) {
                lensName.text = l.name
                mountField.text = l.mount
                selApertures = (l.apertures && l.apertures.length > 0) ? l.apertures.split(",") : []
                selSpeeds = (l.speeds && l.speeds.length > 0) ? l.speeds.split(",") : []
                gen++
            }
        }
    }

    function apSelected(a) { return selApertures.indexOf(a) !== -1 }
    function spSelected(s) { return selSpeeds.indexOf(s) !== -1 }

    Component {
        id: pillComponent
        Rectangle {
            property bool selected: false
            property string label: ""
            property var onToggle
            width: pillLabel.implicitWidth + Theme.paddingLarge * 2
            height: pillLabel.implicitHeight + Theme.paddingMedium
            radius: height / 2
            color: selected ? FiatLuxTheme.amberMed : FiatLuxTheme.deepBg
            border.color: selected ? FiatLuxTheme.amber : FiatLuxTheme.rim
            border.width: selected ? 2 : 1
            Text {
                id: pillLabel; anchors.centerIn: parent; text: parent.label
                color: parent.selected ? FiatLuxTheme.amber : FiatLuxTheme.primaryText
                font.pixelSize: Theme.fontSizeSmall
            }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    parent.selected = !parent.selected
                    if (parent.onToggle) parent.onToggle(parent.selected)
                }
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

            Item {
                width: parent.width; height: Theme.itemSizeLarge
                Text {
                    anchors.centerIn: parent
                    text: editId >= 0 ? "edit lens" : "add lens"
                    color: FiatLuxTheme.primaryText
                    font.pixelSize: Theme.fontSizeLarge
                    font.family: FiatLuxTheme.serif; font.italic: true
                }
            }

            CardSection {
                title: "lens"
                TextField {
                    id: lensName
                    width: parent.width
                    placeholderText: "e.g. SMC Pentax 50mm f/1.7"
                    label: "Lens name"
                    color: FiatLuxTheme.primaryText
                }
                TextField {
                    id: mountField
                    width: parent.width
                    placeholderText: "e.g. M42, K-mount"
                    label: "Mount"
                    color: FiatLuxTheme.primaryText
                }
                Flow {
                    visible: knownMounts.length > 0
                    width: parent.width; spacing: Theme.paddingSmall
                    Repeater {
                        model: knownMounts
                        delegate: BackgroundItem {
                            width: mtag.width + Theme.paddingMedium * 2
                            height: mtag.height + Theme.paddingSmall * 1.5
                            onClicked: mountField.text = modelData
                            Rectangle {
                                anchors.fill: parent; radius: height / 2
                                color: "transparent"
                                border.color: FiatLuxTheme.rim; border.width: 1
                            }
                            Text {
                                id: mtag; anchors.centerIn: parent; text: modelData
                                color: FiatLuxTheme.secondaryText
                                font.pixelSize: Theme.fontSizeExtraSmall
                            }
                        }
                    }
                }
            }

            CardSection {
                title: "apertures"
                Flow {
                    width: parent.width; spacing: Theme.paddingSmall
                    Repeater {
                        model: (gen, allApertures.slice())
                        delegate: Loader {
                            sourceComponent: pillComponent
                            onLoaded: {
                                item.label = "f/" + modelData
                                item.selected = apSelected(modelData)
                                item.onToggle = function(sel) {
                                    if (sel) selApertures.push(modelData)
                                    else selApertures = selApertures.filter(function(a){ return a !== modelData })
                                }
                            }
                        }
                    }
                }
            }

            // Speeds — only relevant for fixed/leaf lenses. For SLR lenses the
            // body supplies speeds, so this section is optional. We always show
            // it; leave empty for an SLR lens.
            CardSection {
                title: "shutter speeds (leaf / fixed lenses only)"
                Text {
                    width: parent.width
                    text: "Leave empty for SLR / rangefinder lenses — the body provides speeds."
                    color: FiatLuxTheme.secondaryText
                    font.pixelSize: Theme.fontSizeExtraSmall
                    wrapMode: Text.Wrap
                }
                Flow {
                    width: parent.width; spacing: Theme.paddingSmall
                    Repeater {
                        model: (gen, allSpeeds.slice())
                        delegate: Loader {
                            sourceComponent: pillComponent
                            onLoaded: {
                                item.label = modelData
                                item.selected = spSelected(modelData)
                                item.onToggle = function(sel) {
                                    if (sel) selSpeeds.push(modelData)
                                    else selSpeeds = selSpeeds.filter(function(s){ return s !== modelData })
                                }
                            }
                        }
                    }
                }
            }

            BackgroundItem {
                id: saveBtn
                width: parent.width; height: Theme.itemSizeLarge
                enabled: page.canSave
                opacity: enabled ? 1.0 : 0.35
                onClicked: {
                    if (editId >= 0)
                        Storage.updateLens(editId, lensName.text, mountField.text, selApertures.join(","), selSpeeds.join(","))
                    else
                        Storage.addLens(lensName.text, mountField.text, selApertures.join(","), selSpeeds.join(","))
                    app.reloadLenses()
                    pageStack.pop()
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    height: Theme.itemSizeMedium; radius: Theme.paddingLarge
                    color: saveBtn.highlighted ? FiatLuxTheme.amberStrong : FiatLuxTheme.amber
                    Text {
                        anchors.centerIn: parent
                        text: editId >= 0 ? "save changes" : "save lens"
                        color: FiatLuxTheme.deepBg
                        font.pixelSize: Theme.fontSizeMedium
                        font.family: FiatLuxTheme.serif; font.italic: true; font.bold: true
                    }
                }
            }

            Item { width: 1; height: Theme.paddingLarge }
        }
    }
}
