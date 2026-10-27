import QtQuick
import qs.Commons
import qs.Commons as Commons

// One key, drawn as a key cap. `big` is the 40 s idle hint.
Rectangle {
    id: cap

    property string label: ""
    property bool big: false
    property bool lit: false
    // Outlined in the accent: the key to look for.
    property bool marked: false

    readonly property int pad: Style.space(big ? 10 : 6)

    implicitWidth: Math.max(implicitHeight, text.implicitWidth + pad * 2)
    implicitHeight: text.implicitHeight + pad * 1.4
    radius: Math.max(Style.cornerRadius, Style.space(4))
    color: lit ? Commons.Color.accent : Commons.Color.menu.selectedBackground
    border.width: marked ? 2 : 1
    border.color: lit || marked ? Commons.Color.accent : Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.35)

    Behavior on implicitHeight { NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic } }
    Behavior on color { ColorAnimation { duration: Style.duration(160) } }

    // The cap's lower edge, so it reads as a key rather than a tag.
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 1 }
        height: Math.max(2, Style.space(2))
        radius: parent.radius
        color: Qt.rgba(0, 0, 0, 0.25)
    }

    Text {
        id: text
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -1
        text: cap.label
        color: cap.lit ? Commons.Color.background : cap.marked ? Commons.Color.accent : Commons.Color.foreground
        font.family: Style.font.family
        font.pixelSize: cap.big ? Style.font.heading : Style.font.body
        font.weight: Font.DemiBold
    }
}
