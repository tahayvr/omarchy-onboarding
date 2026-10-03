import QtQuick
import qs.Commons

// Omi, the step's title and a pause button. The card's text below is Omi
// talking. Progress is the line along the card's top border (ProgressLine).
Item {
    id: header

    property var host
    property var step: null
    // Omi's size; the finish screen makes it bigger.
    property int omiSize: Style.space(48)

    width: parent ? parent.width : implicitWidth
    implicitHeight: Math.max(omi.height, titles.implicitHeight)

    CardOmi {
        id: omi
        host: header.host
        width: header.omiSize
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
    }

    Column {
        id: titles
        anchors { left: omi.right; leftMargin: Style.space(10); right: pauseKey.visible ? pauseKey.left : pauseButton.left; rightMargin: Style.space(8); verticalCenter: parent.verticalCenter }
        // The title, or Omi's confirmation once the step is done: in the
        // accent, faded in, as Omi's own words.
        Text {
            id: titleText
            readonly property bool cheering: !!header.host && header.host.cheering !== ""
            width: parent.width
            text: cheering ? header.host.cheering : header.step ? header.step.title : ""
            wrapMode: Text.Wrap
            color: cheering ? Color.accent : Color.foreground
            onCheeringChanged: if (cheering) cheerIn.restart()
            NumberAnimation { id: cheerIn; target: titleText; property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.weight: Font.DemiBold
        }
    }

    // The ✕'s key, while the tutorial's keys are bound (Ctrl + Esc).
    KeyChip {
        id: pauseKey
        anchors { right: pauseButton.left; rightMargin: Style.space(8); verticalCenter: pauseButton.verticalCenter }
        key: header.host && header.host.tutorialKeys ? (header.host.tutorialKeys.pause || "") : ""
    }

    Text {
        id: pauseButton
        // Pinned to the top-right corner, whatever the height of Omi and the title.
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
            // On the finish screen ✕ finishes, like Esc there.
            onClicked: header.step && header.step.id === "finish" ? header.host.next() : header.host.askPause()
        }
    }
}
