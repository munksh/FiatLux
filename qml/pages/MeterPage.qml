import QtQuick 2.0
import Sailfish.Silica 1.0
import QtMultimedia 5.0

Page {
    id: page
    allowedOrientations: Orientation.Portrait

    property string cameraName: "Quick Meter"
    property string filmName: ""
    property string lens: ""
    property int iso: 400
    property bool isoLocked: false
    property var apertures: ["1", "1.4", "1.7", "2", "2.8", "4", "5.6", "8", "11", "16", "22"]
    property var shutterSpeeds: ["1/1000", "1/500", "1/250", "1/125", "1/60", "1/30", "1/15", "1/8", "1/4", "1/2", "1\""]
    property real ev: 8.0
    property bool editingIso: false

    property bool darkTheme: Theme.colorScheme === Theme.LightOnDark
    property color cardColor: darkTheme ? Qt.rgba(0.08, 0.08, 0.08, 1.0) : Qt.rgba(0.96, 0.96, 0.96, 1.0)
    property color cardBorder: Theme.rgba(Theme.primaryColor, 0.45)

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

        // Camera name header
        Item {
            width: page.width
            height: Theme.itemSizeSmall

            Label {
                anchors.centerIn: parent
                text: cameraName
                color: Theme.primaryColor
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.DemiBold
                font.letterSpacing: Theme.pixelRatio * 1.5
            }
        }

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
                font.weight: Font.DemiBold
            }
        }

        // Exposure pair scroller
        Item {
            width: page.width
            height: Theme.itemSizeLarge * 2 + Theme.paddingMedium * 2

            // Card behind the scroller
            Rectangle {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                height: parent.height - Theme.paddingMedium
                anchors.verticalCenter: parent.verticalCenter
                radius: Theme.paddingLarge * 1.5
                color: page.cardColor
                border.color: page.cardBorder
                border.width: 2
            }

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
                    height: Theme.itemSizeLarge * 2 + Theme.paddingMedium * 2
                    property bool isCenter: ListView.isCurrentItem
                    property int shutterIdx: calcShutterIndex(index)

                    // Highlight behind center pair
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width - Theme.paddingSmall * 2
                        height: parent.height - Theme.paddingLarge * 2
                        radius: Theme.paddingLarge
                        color: Theme.rgba(Theme.highlightColor, 0.15)
                        border.color: Theme.rgba(Theme.highlightColor, 0.45)
                        border.width: 1
                        visible: isCenter
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: Theme.paddingSmall

                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: shutterSpeeds[shutterIdx]
                            color: isCenter ? Theme.highlightColor : Theme.secondaryColor
                            font.pixelSize: isCenter ? Theme.fontSizeLarge : Theme.fontSizeMedium
                            font.weight: isCenter ? Font.Bold : Font.DemiBold
                        }
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "f/" + apertures[index]
                            color: isCenter ? Theme.primaryColor : Theme.secondaryColor
                            font.pixelSize: isCenter ? Theme.fontSizeLarge : Theme.fontSizeMedium
                            font.weight: isCenter ? Font.Bold : Font.DemiBold
                        }
                    }
                }
            }
        }

        Item { width: 1; height: Theme.paddingMedium }

        // Info card — ISO, film, lens
        Item {
            width: page.width
            height: infoCard.height + Theme.paddingSmall * 2

            Rectangle {
                id: infoCard
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                height: infoRow.height + Theme.paddingMedium * 2
                radius: Theme.paddingLarge * 1.5
                color: page.cardColor
                border.color: page.cardBorder
                border.width: 2

                Row {
                    id: infoRow
                    x: Theme.paddingMedium
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.paddingSmall

                    IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        icon.source: editingIso
                            ? "image://theme/icon-m-accept"
                            : "image://theme/icon-m-edit"
                        onClicked: editingIso = !editingIso
                    }

                    // ISO pill / editor
                    Rectangle {
                        visible: !editingIso
                        anchors.verticalCenter: parent.verticalCenter
                        radius: height / 2
                        color: Theme.rgba(Theme.primaryColor, 0.15)
                        border.color: Theme.rgba(Theme.primaryColor, 0.55)
                        border.width: 1
                        width: isoLabel.width + Theme.paddingMedium * 2
                        height: isoLabel.height + Theme.paddingSmall * 1.5
                        Label {
                            id: isoLabel
                            anchors.centerIn: parent
                            text: "ISO " + iso
                            color: Theme.primaryColor
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.DemiBold
                        }
                    }

                    TextField {
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

                    // Film pill
                    Rectangle {
                        visible: filmName.length > 0
                        anchors.verticalCenter: parent.verticalCenter
                        radius: height / 2
                        color: Theme.rgba(Theme.primaryColor, 0.15)
                        border.color: Theme.rgba(Theme.primaryColor, 0.55)
                        border.width: 1
                        width: filmPillLabel.width + Theme.paddingMedium * 2
                        height: filmPillLabel.height + Theme.paddingSmall * 1.5
                        Label {
                            id: filmPillLabel
                            anchors.centerIn: parent
                            text: filmName
                            color: Theme.primaryColor
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.DemiBold
                        }
                    }

                    // Lens pill
                    Rectangle {
                        visible: lens.length > 0
                        anchors.verticalCenter: parent.verticalCenter
                        radius: height / 2
                        color: Theme.rgba(Theme.primaryColor, 0.15)
                        border.color: Theme.rgba(Theme.primaryColor, 0.55)
                        border.width: 1
                        width: Math.min(
                            lensPillLabel.implicitWidth + Theme.paddingMedium * 2,
                            page.width - 2 * Theme.horizontalPageMargin - 180
                        )
                        height: lensPillLabel.height + Theme.paddingSmall * 1.5
                        Label {
                            id: lensPillLabel
                            anchors.centerIn: parent
                            width: parent.width - Theme.paddingMedium * 2
                            text: lens
                            color: Theme.primaryColor
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.DemiBold
                            truncationMode: TruncationMode.Fade
                        }
                    }
                }
            }
        }

        Item { width: 1; height: Theme.paddingLarge }

        // Measure button
        Button {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Measure"
            onClicked: {
                ev = 8.0
            }
        }
    }
}
