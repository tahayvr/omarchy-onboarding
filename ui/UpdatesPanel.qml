import QtQuick
import qs.Commons

// Step 16: whether an update is waiting, and the one safe way to run it.
Column {
    id: panel
    property var host
    spacing: Style.space(10)

    Line {
        text: panel.host.updating ? "Updating in the terminal. This card moves on when it closes."
            : panel.host.updateStatus === "available" ? "An Omarchy update is available."
            : panel.host.updateStatus === "current" ? "✓  Omarchy is up to date."
            : panel.host.updateStatus === "checking" ? "Checking for updates…"
            : "Couldn't check for updates right now."
        color: panel.host.updateStatus === "available" ? Color.accent : Color.foreground
    }
    Button {
        visible: !panel.host.updating
        text: "Update now"
        primary: panel.host.updateStatus === "available"
        onClicked: panel.host.askUpdate()
    }
}
