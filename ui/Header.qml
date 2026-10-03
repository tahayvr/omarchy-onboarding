import QtQuick
import qs.Commons
import "../lib/Ui.js" as Ui

// Omi, the step's title and a pause button. The card's text below is Omi
// talking. Progress is the line along the card's top border (ProgressLine).
Item {
    id: header

    property var host
    property var step: null
    // Omi's size; the finish screen makes it bigger.
    property real omiSize: Style.space(48)

    width: parent ? parent.width : implicitWidth
    implicitHeight: Math.max(omi.height, titles.implicitHeight)

    CardOmi {
        id: omi
        host: header.host
        size: header.omiSize
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
    }

    Column {
        id: titles
        anchors { left: omi.right; leftMargin: Style.space(10); right: pauseKey.visible ? pauseKey.left : pauseButton.left; rightMargin: Style.space(8); verticalCenter: parent.verticalCenter }
        spacing: Style.space(1)
        // Where this step sits: "Learn the keys · 3 of 7".
        Text {
            width: parent.width
            visible: text !== ""
            text: header.host && header.step ? Ui.positionLabel(header.host.steps, header.step.id) : ""
            elide: Text.ElideRight
            color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.62)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
        }
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

    // The ✕'s key: plain Esc on a centered card, which has the keyboard;
    // on the corner card it's Ctrl + Esc, and the footer's "Ctrl + key"
    // legend says so for every chip on the card.
    KeyChip {
        id: pauseKey
        anchors { right: pauseButton.left; rightMargin: Style.space(8); verticalCenter: pauseButton.verticalCenter }
        key: header.step && Ui.isCentered(header.step.id) ? "Esc"
           : header.host && header.host.tutorialKeys ? (header.host.tutorialKeys.pause || "") : ""
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
