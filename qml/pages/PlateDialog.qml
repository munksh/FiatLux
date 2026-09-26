import QtQuick 2.0
import Sailfish.Silica 1.0
import "../Gear.js" as Gear
import ".." 1.0
import "../components"

// Choosing speeds, apertures or a film speed off the plate.
//
// A Dialog, so it behaves like every other Sailfish choice page: cancel and
// accept in the top corners, or swipe forward to accept. Several values for
// speeds and apertures; one for ISO, which accepts as soon as it is tapped.
//
//   var d = pageStack.push(Qt.resolvedUrl("PlateDialog.qml"), { kind: "speeds", selected: [...] })
//   d.accepted.connect(function() { page.speeds = d.selected })

Dialog {
    id: dialog
    allowedOrientations: Orientation.Portrait

    property string kind: "speeds"          // "speeds", "apertures" or "iso"
    property var selected: []
    property string owner: ""                // the camera or lens, for the caption
    property bool allowEmpty: false

    readonly property bool single: kind === "iso"
    property var fresh: []

    readonly property string title: kind === "speeds" ? qsTr("shutter speeds")
                                  : kind === "apertures" ? qsTr("apertures")
                                  : qsTr("film speed")
    readonly property string hint: kind === "speeds" ? qsTr("Only the ones on the dial. Lux only suggests speeds you can set.")
                                 : kind === "apertures" ? qsTr("The stops marked on the ring. Half and third stops between them count too, if the ring clicks there.")
                                 : qsTr("The ISO to meter at.")
    readonly property string captionRight: kind === "speeds" ? qsTr("speeds · seconds")
                                         : kind === "apertures" ? qsTr("apertures · f-number")
                                         : qsTr("ISO")
    readonly property string customLabel: kind === "speeds" ? qsTr("+ a speed not listed")
                                        : kind === "apertures" ? qsTr("+ an aperture not listed")
                                        : qsTr("+ another film speed")

    canAccept: single ? selected.length === 1 : (allowEmpty || selected.length > 0)

    function sorted(list) {
        if (kind === "speeds") return Gear.speedsForStorage(list)
        if (kind === "apertures") return Gear.sortApertures(list)
        return Gear.unique(list)
    }

    function toggle(v) {
        if (single) {
            selected = [v]
            dialog.accept()
            return
        }
        var out = selected.slice()
        var i = out.indexOf(v)
        if (i === -1) out.push(v)
        else out.splice(i, 1)
        selected = sorted(out)
    }

    function addCustom() {
        var v = kind === "speeds" ? Gear.normaliseSpeed(customField.text)
              : kind === "apertures" ? Gear.normaliseAperture(customField.text)
              : Gear.normaliseIso(customField.text)
        if (v === "") {
            customError.visible = true
            return
        }
        customError.visible = false
        customField.text = ""
        customRow.open = false
        var f = fresh.slice()
        f.push(v)
        fresh = f
        if (single) {
            selected = [v]
            dialog.accept()
            return
        }
        if (selected.indexOf(v) === -1) selected = sorted(selected.concat([v]))
    }

    function paint() { FiatLuxTheme.applyPalette(dialog) }
    Component.onCompleted: {
        paint()
        selected = sorted(selected)
    }

    PaperBackground { }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingMedium

            // ---- cancel · accept, on the status row ----
            Item {
                width: parent.width
                height: FiatLuxTheme.statusRowCenter * 2

                LinkText {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.horizontalPageMargin - Theme.paddingSmall
                    y: FiatLuxTheme.statusRowCenter - height / 2
                    text: qsTr("cancel")
                    underline: false
                    color: FiatLuxTheme.secondaryText
                    fontSize: Theme.fontSizeMedium
                    onClicked: dialog.reject()
                }
                LinkText {
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.horizontalPageMargin - Theme.paddingSmall
                    y: FiatLuxTheme.statusRowCenter - height / 2
                    visible: !dialog.single
                    enabled: dialog.canAccept
                    text: qsTr("accept")
                    underline: false
                    fontSize: Theme.fontSizeMedium
                    onClicked: dialog.accept()
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                text: dialog.title
                color: FiatLuxTheme.primaryText
                font.pixelSize: Theme.fontSizeLarge
                font.family: FiatLuxTheme.serif
            }

            FormNote {
                text: dialog.hint
            }

            // ---- whole series in one tap ----
            Row {
                visible: dialog.kind !== "iso"
                x: dialog.kind === "speeds" ? Theme.horizontalPageMargin : Theme.horizontalPageMargin - Theme.paddingSmall
                spacing: 0

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: dialog.kind === "speeds" ? qsTr("start from") : ""
                    visible: text !== ""
                    color: FiatLuxTheme.secondaryText
                    font.pixelSize: Theme.fontSizeSmall
                }
                LinkText {
                    visible: dialog.kind === "speeds"
                    text: qsTr("modern")
                    onClicked: dialog.selected = Gear.speedsForStorage(Gear.modernSpeeds)
                }
                LinkText {
                    visible: dialog.kind === "speeds"
                    text: qsTr("classic")
                    onClicked: dialog.selected = Gear.speedsForStorage(Gear.classicSpeeds)
                }
                LinkText {
                    visible: dialog.kind === "apertures"
                    text: qsTr("fill in the full stops")
                    onClicked: dialog.selected = Gear.fillFullStops(dialog.selected)
                }
                LinkText {
                    visible: dialog.selected.length > 0
                    text: qsTr("clear")
                    color: FiatLuxTheme.secondaryText
                    onClicked: dialog.selected = []
                }
            }

            ValuePlate {
                groups: Gear.mergedGroups(dialog.kind, dialog.selected.concat(dialog.fresh))
                selected: dialog.selected
                fresh: dialog.fresh
                prefix: dialog.kind === "apertures" ? "f/" : ""
                captionLeft: dialog.owner
                captionRight: dialog.captionRight
                onToggled: dialog.toggle(value)
            }

            // ---- a value the plate does not have ----
            Column {
                id: customRow
                property bool open: false
                width: parent.width

                LinkText {
                    visible: !customRow.open
                    x: Theme.horizontalPageMargin - Theme.paddingSmall
                    text: dialog.customLabel
                    underline: false
                    italic: true
                    onClicked: {
                        customRow.open = true
                        customField.forceActiveFocus()
                    }
                }

                Row {
                    visible: customRow.open
                    width: parent.width
                    TextField {
                        id: customField
                        width: parent.width - addButton.width
                        label: dialog.kind === "speeds" ? qsTr("e.g. 1/320 or 3 s")
                             : dialog.kind === "apertures" ? qsTr("e.g. 2.4")
                             : qsTr("e.g. 12")
                        placeholderText: label
                        color: FiatLuxTheme.primaryText
                        inputMethodHints: dialog.kind === "speeds" ? Qt.ImhNoPredictiveText
                                                                   : Qt.ImhFormattedNumbersOnly
                        EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                        EnterKey.onClicked: dialog.addCustom()
                    }
                    LinkText {
                        id: addButton
                        anchors.top: parent.top
                        anchors.topMargin: Theme.paddingMedium
                        text: qsTr("add")
                        underline: false
                        onClicked: dialog.addCustom()
                    }
                }

                FormNote {
                    id: customError
                    visible: false
                    color: FiatLuxTheme.outOfRange
                    text: dialog.kind === "speeds" ? qsTr("Write it like 1/320, or 3 s for seconds.")
                        : dialog.kind === "apertures" ? qsTr("Write the f-number, like 2.4.")
                        : qsTr("Write a whole number, like 12.")
                }
            }

            Item { width: 1; height: Theme.paddingLarge }
        }

        VerticalScrollDecorator { }
    }
}
