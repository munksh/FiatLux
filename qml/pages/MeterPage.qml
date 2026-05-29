import QtQuick 2.0
import Sailfish.Silica 1.0
import QtMultimedia 5.0

Page {
    id: page
    allowedOrientations: Orientation.Portrait

    // Profile info — passed in or defaulted
    property string cameraName: "Quick Meter"
    property string filmName: ""
    property string lens: ""
    property int iso: 400
    property bool isoLocked: false
    property var apertures: ["1", "1.4", "1.7", "2", "2.8", "4", "5.6", "8", "11", "16", "22"]
    property var shutterSpeeds: ["1/1000", "1/500", "1/250", "1/125", "1/60", "1/30", "1/15", "1/8", "1/4", "1/2", "1\""]

    // EV from light measurement
    property real ev: 8.0

    // Whether the user is currently editing ISO
    property bool editingIso: false

    function parseSpeed(s) {
        if (s === "B") return null
        if (s.indexOf("/") !== -1) {
            var parts = s.split("/")
            return parseFloat(parts[0]) / parseFloat(parts[1])
        }
        return parseFloat(s.replace("\"", ""))
    }

    function calcShutterIndex(apertureIndex) {
        var f = parseFloat(apertures[apertureIndex])
        var speed = (f * f) / (Math.pow(2, ev) * (iso / 100))
        var closest = 0
        var diff = Infinity
        for (var i = 0; i < shutterSpeeds.length; i++) {
            var sValue = parseSpeed(shutterSpeeds[i])
            if (sValue === null) continue
            var d = Math.abs(sValue - speed)
            if (d < diff) { diff = d; closest = i }
        }
        return closest
    }

    Camera {
        id: camera
        captureMode: Camera.CaptureViewfinder
    }

    Column {
        anchors.fill: parent
        spacing: 0

        PageHeader { title: cameraName }

        // 1:1 Viewfinder
        Rectangle {
            width: page.width
            height: page.width
            color: "#111111"

            VideoOutput {
                anchors.fill: parent
                source: camera
                fillMode: VideoOutput.PreserveAspectCrop
                visible: camera.availability === Camera.Available
            }

            Label {
                anchors.centerIn: parent
                visible: camera.availability !== Camera.Available
                text: "Camera not available"
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
            }
        }

        // Exposure pair scroller
        Item {
            width: page.width
            height: Theme.itemSizeLarge * 2

            ListView {
                id: exposureList
                anchors.fill: parent
                orientation: ListView.Horizontal
                snapMode: ListView.SnapToItem
                highlightRangeMode: ListView.StrictlyEnforceRange
                preferredHighlightBegin: width / 2 - Theme.itemSizeHuge / 2
                preferredHighlightEnd: width / 2 + Theme.itemSizeHuge / 2
                clip: true
                model: apertures.length

                delegate: Item {
                    width: Theme.itemSizeHuge
                    height: Theme.itemSizeLarge * 2
                    property bool isCenter: ListView.isCurrentItem
                    property int shutterIdx: calcShutterIndex(index)

                    Column {
                        anchors.centerIn: parent
                        spacing: Theme.paddingSmall

                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: shutterSpeeds[shutterIdx]
                            color: isCenter ? Theme.highlightColor : Theme.secondaryColor
                            font.pixelSize: isCenter ? Theme.fontSizeLarge : Theme.fontSizeMedium
                            font.bold: isCenter
                        }

                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "f/" + apertures[index]
                            color: isCenter ? Theme.primaryColor : Theme.secondaryColor
                            font.pixelSize: isCenter ? Theme.fontSizeLarge : Theme.fontSizeMedium
                            font.bold: isCenter
                        }
                    }
                }
            }
        }

        // ISO + film + lens row with lock
        Row {
            x: Theme.horizontalPageMargin
            spacing: Theme.paddingMedium
            width: page.width - 2 * Theme.horizontalPageMargin

            // Lock icon — tap to toggle ISO editing
            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                icon.source: editingIso
                    ? "image://theme/icon-m-accept"
                    : "image://theme/icon-m-edit"
                onClicked: editingIso = !editingIso
            }

            // ISO display or editor
            Label {
                visible: !editingIso
                anchors.verticalCenter: parent.verticalCenter
                text: "ISO " + iso
                color: Theme.primaryColor
                font.pixelSize: Theme.fontSizeSmall
            }

            TextField {
                id: isoEditor
                visible: editingIso
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.itemSizeMedium
                text: iso.toString()
                inputMethodHints: Qt.ImhDigitsOnly
                maximumLength: 4
                validator: IntValidator { bottom: 1; top: 9999 }
                onTextChanged: {
                    var n = parseInt(text)
                    if (!isNaN(n) && n > 0) iso = n
                }
            }

            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: filmName.length > 0 ? "· " + filmName : ""
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
                visible: filmName.length > 0
            }

            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: lens.length > 0 ? "· " + lens : ""
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
                visible: lens.length > 0
                truncationMode: TruncationMode.Fade
            }
        }

        Item { width: 1; height: Theme.paddingLarge }

        Button {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Measure"
            onClicked: {
                ev = 8.0  // real light reading goes here later
            }
        }
    }
}
