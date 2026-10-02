import QtQuick
import qs.Commons

// Step 12: one row per detected item, each done or skipped on its own.
Column {
    id: panel
    property var host
    spacing: Style.space(12)

    Repeater {
        model: panel.host.hardware
        delegate: Column {
            id: item
            required property var modelData
            readonly property string result: panel.host.hardwareState[modelData.id] || ""
            width: panel.width
            spacing: Style.space(6)

            Row {
                width: parent.width
                spacing: Style.space(8)
                Text {
                    text: item.result === "done" ? "✓" : item.result === "skipped" ? "–" : "○"
                    color: item.result ? Color.accent : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.62)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.title
                }
                Column {
                    width: parent.width - Style.space(30)
                    Line { text: item.modelData.title }
                    Line { secondary: true; text: item.modelData.detail }
                }
            }

            Row {
                visible: item.result === "" || item.result === "asking"
                spacing: Style.space(8)
                Button {
                    visible: item.result === ""
                    text: item.modelData.id === "audio" ? "Play test sound"
                        : item.modelData.action.indexOf("panel:") === 0 ? "Open"
                        : item.modelData.id === "firmware" ? "Check" : "Set up"
                    onClicked: panel.host.hardwareAct(item.modelData)
                }
                Line { visible: item.result === "asking"; width: implicitWidth; text: "Heard both sides?" }
                Button { visible: item.result === "asking"; text: "Yes"; primary: true; onClicked: panel.host.hardwareResolve(item.modelData.id, "done") }
                Button { visible: item.result === "asking"; text: "No, open sound settings"; onClicked: panel.host.openPanel("omarchy.audio") }
                Button { text: "Skip"; onClicked: panel.host.hardwareResolve(item.modelData.id, "skipped") }
            }
            Button {
                visible: item.result === "opened"
                text: "Done"
                onClicked: panel.host.hardwareResolve(item.modelData.id, "done")
            }
        }
    }
}
