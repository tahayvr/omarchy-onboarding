import QtQuick
import qs.Commons

// The welcome checklist while it has stepped aside for the network panel, the
// update terminal or the keybindings list. It comes back by itself when that's
// done, or with the button.
Rectangle {
    id: card

    property var host
    // "wifi", "update" or "keys".
    property string reason: ""

    implicitWidth: Style.space(400)
    implicitHeight: column.implicitHeight + Style.space(32)
    color: Color.popups.background
    border.color: Color.popups.border
    border.width: 1
    radius: Style.cornerRadius

    Column {
        id: column
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: Style.space(16) }
        spacing: Style.space(10)

        Text {
            text: "Welcome to Omarchy"
            color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.62)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
        }
        Line {
            text: card.reason === "wifi" ? "Pick your network in the panel. This card returns once you're online."
                : card.reason === "update" ? "Omarchy is updating in the terminal. This card returns when it closes."
                : "Every shortcut, searchable. Press Esc to close the list and come back."
        }
        Button {
            anchors.right: parent.right
            text: "Back to the checklist"
            onClicked: card.host.comeBack()
        }
    }
}
