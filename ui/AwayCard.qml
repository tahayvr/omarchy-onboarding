import QtQuick
import qs.Commons

// The welcome checklist while it has stepped aside (for a panel, the update
// terminal, the keybindings list or the menu). It comes back by itself when
// that closes, or with the button.
Rectangle {
    id: card

    property var host
    // "wifi", "update", "keys", "menu" or "panel" (another shell panel).
    property string reason: ""

    implicitWidth: Style.space(400)
    implicitHeight: column.implicitHeight + Style.space(48)
    color: Color.popups.background
    border.color: Color.popups.border
    border.width: 1
    radius: Style.cornerRadius

    Column {
        id: column
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: Style.space(24) }
        spacing: Style.space(16)

        Row {
            width: parent.width
            spacing: Style.space(14)
            CardOmi { id: omi; host: card.host; anchors.verticalCenter: parent.verticalCenter }
            Line {
                width: parent.width - omi.width - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                text: card.reason === "wifi" ? "Pick your network in the panel. I'll be back once you're online."
                    : card.reason === "update" ? "Omarchy is updating in the terminal. I'll be back when it's done."
                    : card.reason === "menu" ? "Have a look around the menu. Close it and I'll be back."
                    : card.reason === "panel" ? "Take your time in the panel. Close it and I'll be back."
                    : "That's every shortcut, and you can search it. Close it and I'll be back."
            }
        }
        // What closes it (everything but the update terminal closes with
        // Esc), beside the way back.
        Row {
            anchors.right: parent.right
            spacing: Style.space(14)
            KeyCaps {
                visible: card.reason !== "update"
                anchors.verticalCenter: parent.verticalCenter
                keys: "Esc"
            }
            Button {
                text: "Back to the checklist"
                onClicked: card.host.comeBack()
            }
        }
    }
}
