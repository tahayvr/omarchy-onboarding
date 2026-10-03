import QtQuick
import qs.Commons

// The step's title and a pause button. Progress is the line along the card's
// top border (ProgressLine).
Item {
    id: header

    property var host
    property var step: null

    width: parent ? parent.width : implicitWidth
    implicitHeight: titles.implicitHeight

    Column {
        id: titles
        anchors { left: parent.left; right: pauseButton.left; rightMargin: Style.space(8) }
        Text {
            width: parent.width
            text: header.step ? header.step.title : ""
            wrapMode: Text.Wrap
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.weight: Font.DemiBold
        }
    }

    Text {
        id: pauseButton
        anchors { right: parent.right; top: parent.top }
        text: "✕"
        color: closeMouse.containsMouse ? Color.foreground : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.62)
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        MouseArea {
            id: closeMouse
            anchors.fill: parent
            anchors.margins: -Style.space(6)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: header.host.askPause()
        }
    }
}
