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

        Row {
            width: parent.width
            spacing: Style.space(10)
            CardOmi { id: omi; host: card.host; anchors.verticalCenter: parent.verticalCenter }
            Line {
                width: parent.width - omi.width - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                text: card.reason === "wifi" ? "Pick your network in the panel. I'll be back once you're online."
                    : card.reason === "update" ? "Omarchy is updating in the terminal. I'll be back when it's done."
                    : "That's every shortcut, and you can search it. Press Esc and I'll be back."
            }
        }
        Button {
            anchors.right: parent.right
            text: "Back to the checklist"
            onClicked: card.host.comeBack()
        }
    }
}
