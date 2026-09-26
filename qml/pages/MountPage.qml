import QtQuick 2.0
import Sailfish.Silica 1.0
import "../Storage.js" as Storage
import "../Gear.js" as Gear
import ".." 1.0
import "../components"

// Which mount. Not a catalogue to browse, only a way to make "K-mount" and
// "Pentax K" the same thing, because lenses find their camera by the mount
// written on both. Yours first, then the common ones, then anything else.
//
//   var p = pageStack.push(Qt.resolvedUrl("MountPage.qml"), { current: m })
//   p.picked.connect(function(mount) { ... })

Page {
    id: page
    allowedOrientations: Orientation.Portrait

    property string current: ""
    signal picked(string mount)

    property var yours: []
    property string query: ""

    function paint() { FiatLuxTheme.applyPalette(page) }
    Component.onCompleted: {
        paint()
        yours = Storage.mounts()
    }

    function choose(m) {
        var name = ("" + m).trim()
        if (name.length === 0) return
        page.picked(name)
        pageStack.pop()
    }

    function matches(m, q) {
        if (q.length === 0) return true
        var hay = (m.name + " " + (m.note || "") + " " + (m.also || "")).toLowerCase()
        return hay.indexOf(q) !== -1
    }

    readonly property var rows: {
        var q = page.query.trim().toLowerCase()
        var out = []
        var taken = {}
        var i
        var mine = page.yours.filter(function(m) { return page.matches({ name: m }, q) })
        for (i = 0; i < mine.length; i++) {
            out.push({ section: i === 0 ? qsTr("yours") : "", name: mine[i], note: "" })
            taken[mine[i].toLowerCase()] = true
        }
        var first = true
        for (i = 0; i < Gear.mounts.length; i++) {
            var m = Gear.mounts[i]
            if (taken[m.name.toLowerCase()] || !page.matches(m, q)) continue
            out.push({ section: first ? qsTr("common") : "", name: m.name, note: m.note })
            first = false
        }
        return out
    }

    PaperBackground { }

    SilicaListView {
        id: list
        anchors.fill: parent
        model: page.rows

        header: Column {
            width: list.width

            PageHead {
                title: qsTr("mount")
                subtitle: "fiat lux"
            }

            SearchField {
                id: search
                width: parent.width
                placeholderText: qsTr("search mounts")
                color: FiatLuxTheme.primaryText
                onTextChanged: page.query = text
                EnterKey.onClicked: if (text.trim().length > 0 && page.rows.length === 0) page.choose(text)
            }
        }

        delegate: Column {
            width: list.width

            SectionTitle {
                visible: modelData.section !== ""
                text: modelData.section
            }

            BackgroundItem {
                width: parent.width
                height: Theme.itemSizeSmall
                highlightedColor: FiatLuxTheme.highlightWash
                onClicked: page.choose(modelData.name)

                readonly property bool on: modelData.name === page.current

                Label {
                    id: mountName
                    x: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.name
                    color: parent.on ? FiatLuxTheme.accent : FiatLuxTheme.primaryText
                    font.pixelSize: Theme.fontSizeMedium
                    font.bold: parent.on
                }
                Label {
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.horizontalPageMargin
                    anchors.left: mountName.right
                    anchors.leftMargin: Theme.paddingLarge
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    truncationMode: TruncationMode.Fade
                    text: modelData.note
                    color: FiatLuxTheme.secondaryText
                    font.pixelSize: Theme.fontSizeExtraSmall
                }
            }
        }

        footer: Column {
            id: another
            width: list.width
            property bool open: false

            // Searching for something that is not here: offer it as typed.
            BackgroundItem {
                visible: page.query.trim().length > 0
                width: parent.width
                height: Theme.itemSizeSmall
                highlightedColor: FiatLuxTheme.highlightWash
                onClicked: page.choose(page.query)
                Label {
                    x: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Theme.horizontalPageMargin * 2
                    truncationMode: TruncationMode.Fade
                    text: qsTr("use “%1”").arg(page.query.trim())
                    color: FiatLuxTheme.accent
                    font.pixelSize: Theme.fontSizeSmall
                    font.family: FiatLuxTheme.serif
                    font.italic: true
                }
            }

            LinkText {
                visible: !another.open && page.query.trim().length === 0
                x: Theme.horizontalPageMargin - Theme.paddingSmall
                text: qsTr("+ another mount")
                underline: false
                italic: true
                onClicked: {
                    another.open = true
                    otherField.forceActiveFocus()
                }
            }

            TextField {
                id: otherField
                visible: another.open
                width: parent.width
                label: qsTr("Mount name")
                placeholderText: qsTr("e.g. Rolleiflex SL66")
                color: FiatLuxTheme.primaryText
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: page.choose(text)
            }

            FormNote {
                text: qsTr("Lenses fit a camera when both have the same mount.")
            }

            Item { width: 1; height: Theme.paddingLarge }
        }

        VerticalScrollDecorator { }
    }
}
