import QtQuick 2.0
import Sailfish.Silica 1.0
import ".." 1.0

CoverBackground {
    id: cover

    Rectangle {
        anchors.fill: parent
        color: FiatLuxTheme.deepBg
    }

    Column {
        anchors.centerIn: parent
        spacing: Theme.paddingLarge

        Canvas {
            width: 96; height: 58
            anchors.horizontalCenter: parent.horizontalCenter
            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.beginPath(); ctx.arc(48, 58, 48, Math.PI, 0)
                ctx.fillStyle = "#F4EED8"; ctx.fill()
                ctx.beginPath(); ctx.ellipse(0, 50, 96, 16)
                ctx.fillStyle = "#D8CEAE"; ctx.fill()
                ctx.beginPath(); ctx.arc(34, 30, 11, Math.PI * 1.1, Math.PI * 1.75)
                ctx.strokeStyle = "rgba(255,255,255,0.35)"
                ctx.lineWidth = 4; ctx.lineCap = "round"; ctx.stroke()
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "fiat lux"
            color: FiatLuxTheme.primaryText
            font.pixelSize: Theme.fontSizeLarge
            font.family: FiatLuxTheme.serif
            font.italic: true
        }
    }
}
