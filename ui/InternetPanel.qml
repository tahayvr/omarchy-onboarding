import QtQuick
import qs.Commons

// Step 2: the real network panel does the work; this shows when it worked.
Column {
    id: panel
    property var host
    spacing: Style.space(10)

    Line {
        text: panel.host.facts.online ? "✓  Connected" : "Not connected yet. Checking every 2 seconds."
        color: panel.host.facts.online ? Color.accent : Color.foreground
    }
    Button { text: "Open the network panel"; onClicked: panel.host.openPanel("omarchy.network") }
}
