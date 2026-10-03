import QtQuick
import qs.Commons

// Omi, the step's title and a pause button. The card's text below is Omi
// talking. Progress is the line along the card's top border (ProgressLine).
Item {
    id: header

    property var host
    property var step: null

    width: parent ? parent.width : implicitWidth
    implicitHeight: Math.max(omi.height, titles.implicitHeight)

    CardOmi {
        id: omi
        host: header.host
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
    }

    Column {
        id: titles
        anchors { left: omi.right; leftMargin: Style.space(10); right: pauseButton.left; rightMargin: Style.space(8); verticalCenter: parent.verticalCenter }
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
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
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
