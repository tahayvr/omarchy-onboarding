import QtQuick
import qs.Commons

// A key, drawn small and muted, beside the control it works: inside a button,
// or next to the ✕. Not a second button: the theme's background showing
// through faintly on an accent fill, the foreground faintly on a plain one,
// and no border, so it doesn't echo the control's own outline.
Rectangle {
    id: chip

    property string key: ""
    // On an accent fill (a primary button) rather than a plain one.
    property bool onAccent: false

    readonly property color ink: onAccent ? Color.background : Color.foreground

    visible: key !== ""
    implicitWidth: Math.max(implicitHeight, label.implicitWidth + Style.space(8))
    implicitHeight: label.implicitHeight + Style.space(4)
    radius: Math.max(Style.cornerRadius, Style.space(3))
    color: onAccent ? Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.22)
                    : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1)

    Text {
        id: label
        anchors.centerIn: parent
        text: chip.key
        color: Qt.rgba(chip.ink.r, chip.ink.g, chip.ink.b, 0.6)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
    }
}
