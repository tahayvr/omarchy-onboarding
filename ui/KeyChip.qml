import QtQuick
import qs.Commons
import qs.Commons as Commons

// A key, drawn small and muted, beside the control it works: inside a button,
// or next to the ✕. Not a second button: the theme's background showing
// through faintly on an accent fill, the foreground faintly on a plain one,
// and no border, so it doesn't echo the control's own outline.
Rectangle {
    id: chip

    property string key: ""
    // On an accent fill (a primary button) rather than a plain one.
    property bool onAccent: false

    readonly property color ink: onAccent ? Commons.Color.background : Commons.Color.foreground

    visible: key !== ""
    implicitWidth: Math.max(implicitHeight, label.implicitWidth + Style.space(8))
    implicitHeight: label.implicitHeight + Style.space(4)
    radius: Math.max(Style.cornerRadius, Style.space(3))
    color: onAccent ? Qt.rgba(Commons.Color.background.r, Commons.Color.background.g, Commons.Color.background.b, 0.22)
                    : Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.1)

    Text {
        id: label
        anchors.centerIn: parent
        text: chip.key
        color: Qt.rgba(chip.ink.r, chip.ink.g, chip.ink.b, 0.6)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
    }
}
