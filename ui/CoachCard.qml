import QtQuick
import Quickshell.Hyprland
import qs.Commons
import "../lib/Ui.js" as Ui

// The corner card for the "Learn to move" drills. It never takes the
// keyboard (the drills need Super shortcuts to reach Hyprland), except the
// clipboard step's field, which the user clicks to paste into.
Rectangle {
    id: card

    property var host
    property var step: null
    property var ticked: ({})
    property int hint: 0
    property alias pasteField: field

    readonly property bool isWorkspaces: step && step.id === "workspaces"
    readonly property bool isClipboard: step && step.id === "clipboard"

    implicitWidth: Style.space(460)
    implicitHeight: column.implicitHeight + Style.space(32)

    ProgressLine { progress: card.host ? card.host.progress : -1 }
    color: Color.popups.background
    border.color: Color.popups.border
    border.width: 1
    radius: Style.cornerRadius

    Column {
        id: column
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: Style.space(16) }
        spacing: Style.space(12)

        Header { host: card.host; step: card.step }

        Text {
            width: parent.width
            visible: text !== ""
            text: card.step ? (card.step.screen || "") : ""
            wrapMode: Text.Wrap
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
        }

        Column {
            width: parent.width
            spacing: Style.space(8)
            Repeater {
                model: card.step && card.step.subtasks ? card.step.subtasks : []
                delegate: Subtask {
                    required property var modelData
                    width: parent.width
                    label: modelData.label
                    keys: modelData.keys || ""
                    done: !!card.ticked[modelData.id]
                    big: card.hint > 0
                }
            }
        }

        // Mirrors the bar's workspace indicator, so the jump is easy to follow.
        Row {
            visible: card.isWorkspaces
            spacing: Style.space(6)
            Repeater {
                model: [1, 2, 3, 4]
                delegate: Rectangle {
                    required property int modelData
                    readonly property bool here: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData
                    width: Style.space(30)
                    height: Style.space(24)
                    radius: Style.cornerRadius
                    color: here ? Color.accent : Style.normalFill
                    border.width: 1
                    border.color: here ? Color.accent : Style.normalBorderColor
                    Text {
                        anchors.centerIn: parent
                        text: modelData
                        color: parent.here ? Color.background : Color.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                    }
                }
            }
        }

        // Step 8's target: paste the copied line here with Super + V.
        Rectangle {
            visible: card.isClipboard
            width: parent.width
            height: field.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: Style.normalFill
            border.width: field.activeFocus ? 2 : 1
            border.color: field.activeFocus ? Color.accent : Style.normalBorderColor

            TextInput {
                id: field
                anchors { fill: parent; margins: Style.space(8) }
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                color: Color.foreground
                selectionColor: Style.selectionFill
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                onTextChanged: card.host.pasted(text)
                Keys.onEscapePressed: card.host.askPause()

                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: !field.text && !field.activeFocus
                    text: "Click here, then press Super + V"
                    color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.62)
                    font: field.font
                }
            }
        }

        // The action steps' own controls.
        Loader {
            width: parent.width
            active: sourceComponent !== null
            sourceComponent: !card.step ? null
                : card.step.id === "display" ? displayPanel
                : card.step.id === "apps" ? appsPanel
                : null
        }

        Footer {
            host: card.host
            hint: card.hint
            canDoIt: !!(card.step && Ui.doItPlan(card.step.id, { ticked: card.ticked, windows: card.host.drillWindows }))
            primaryText: card.host.primaryText
            primaryEnabled: card.host.primaryEnabled
            onPrimary: card.host.primaryAction()
        }
    }

    Component { id: displayPanel; DisplayPanel { host: card.host } }
    Component { id: appsPanel; AppsPanel { host: card.host } }
}
