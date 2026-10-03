import QtQuick
import qs.Commons
import "../lib/Ui.js" as Ui

// Step 11: what Hyprland reports for each screen, live as the scale changes.
Column {
    id: panel
    property var host
    spacing: Style.space(8)

    Repeater {
        model: panel.host.monitors
        delegate: Line {
            required property var modelData
            text: Ui.monitorLine(modelData, panel.host.monitors.length)
        }
    }
    Line {
        visible: panel.host.monitors.length > 1
        secondary: true
        text: "With more than one screen, Display settings arranges them."
    }
    // Omarchy's own bind, so it's shown as key caps beside the button, like
    // a sub-task's, not as the button's key.
    Item {
        width: parent.width
        implicitHeight: Math.max(settingsButton.implicitHeight, settingsCaps.implicitHeight)
        Button {
            id: settingsButton
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            text: "Display settings"
            onClicked: panel.host.openPanel("omarchy.monitor")
        }
        KeyCaps {
            id: settingsCaps
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            keys: "Super + Ctrl + D"
        }
    }
}
