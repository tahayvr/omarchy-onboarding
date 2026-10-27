import QtQuick
import qs.Commons
import qs.Commons as Commons

// Body text for the corner card's panels.
Text {
    property bool secondary: false
    width: parent ? parent.width : implicitWidth
    wrapMode: Text.Wrap
    color: secondary ? Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.62) : Commons.Color.foreground
    font.family: Style.font.family
    font.pixelSize: secondary ? Style.font.bodySmall : Style.font.body
}
