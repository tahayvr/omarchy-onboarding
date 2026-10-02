import QtQuick
import qs.Commons

// Body text for the corner card's panels.
Text {
    property bool secondary: false
    width: parent ? parent.width : implicitWidth
    wrapMode: Text.Wrap
    color: secondary ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.62) : Color.foreground
    font.family: Style.font.family
    font.pixelSize: secondary ? Style.font.bodySmall : Style.font.body
}
