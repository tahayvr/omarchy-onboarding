import QtQuick
import qs.Commons

// Step 11: what Hyprland reports for each screen, live as the scale changes.
Column {
    id: panel
    property var host
    spacing: Style.space(8)

    Repeater {
        model: panel.host.monitors
        delegate: Line {
            required property var modelData
            text: modelData.name + " · " + modelData.width + "×" + modelData.height + " · " + Math.round(modelData.scale * 100) + "%"
        }
    }
    Line {
        visible: panel.host.monitors.length > 1
        secondary: true
        text: "With more than one screen, Display settings arranges them."
    }
    Button { text: "Display settings"; key: "Super + Ctrl + D"; onClicked: panel.host.openPanel("omarchy.monitor") }
}
