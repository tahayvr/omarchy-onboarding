import QtQuick
import Quickshell.Hyprland
import qs.Commons
import "../lib/Ui.js" as Ui

// The corner card for the tutorial's steps. It never takes the keyboard (the
// drills need Super shortcuts to reach Hyprland), except on the clipboard
// step until its line is copied.
Rectangle {
    id: card

    property var host
    property var step: null
    property var ticked: ({})
    property int hint: 0

    readonly property bool isWorkspaces: step && step.id === "workspaces"
    readonly property bool isClipboard: step && step.id === "clipboard"

    // Wide enough for its widest row that can't wrap: the footer's buttons,
    // or the widest key caps with room for a label beside them. Never
    // narrower than the base width, never wider than the cap.
    readonly property real baseWidth: Style.space(480)
    property real capsNeed: 0
    readonly property real panelNeed: panel.item && panel.item.capsNeed !== undefined ? panel.item.capsNeed : 0
    readonly property real rowNeed: Math.max(footer.implicitWidth, Math.max(capsNeed, panelNeed) + Style.space(200))
    implicitWidth: Math.min(Style.space(700), Math.max(baseWidth, rowNeed + Style.space(48)))
    implicitHeight: column.implicitHeight + Style.space(48)

    function measure() {
        var m = 0;
        for (var i = 0; i < subtasks.count; i++) {
            var it = subtasks.itemAt(i);
            if (it) m = Math.max(m, it.capsWidth);
        }
        capsNeed = m;
    }

    ProgressLine { progress: card.host ? card.host.progress : -1 }
    color: Color.popups.background
    border.color: Color.popups.border
    border.width: 1
    radius: Style.cornerRadius

    Column {
        id: column
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: Style.space(24) }
        spacing: Style.space(20)

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
            spacing: Style.space(12)
            Repeater {
                id: subtasks
                model: card.step && card.step.subtasks ? card.step.subtasks : []
                onCountChanged: card.measure()
                onItemAdded: card.measure()
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
            spacing: Style.space(8)
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

        // The clipboard step's line to copy: selected and holding the keyboard
        // (the card takes it until the copy), so Super + C copies it as is.
        Rectangle {
            visible: card.isClipboard
            width: parent.width
            height: sample.implicitHeight + Style.space(20)
            radius: Style.cornerRadius
            color: Style.normalFill
            border.width: sample.activeFocus ? 2 : 1
            border.color: sample.activeFocus ? Color.accent : Style.normalBorderColor

            TextInput {
                id: sample
                anchors { fill: parent; margins: Style.space(10) }
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                readOnly: true
                persistentSelection: true
                selectByMouse: true
                text: Ui.CLIPBOARD_SAMPLE
                color: Color.foreground
                selectionColor: Style.selectionFill
                selectedTextColor: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                Keys.onEscapePressed: card.host.askPause()
                // Selected and focused while there's a copy to make.
                readonly property bool waiting: card.isClipboard && !card.ticked.copy
                onWaitingChanged: if (waiting) grab()
                Component.onCompleted: if (waiting) grab()
                function grab() {
                    selectAll();
                    forceActiveFocus();
                }
            }
        }

        // The action steps' own controls.
        Loader {
            id: panel
            width: parent.width
            sourceComponent: !card.step ? null
                : card.step.id === "display" ? displayPanel
                : null
        }

        Footer {
            id: footer
            host: card.host
            hint: card.hint
            canDoIt: !!(card.step && Ui.doItPlan(card.step.id, { ticked: card.ticked, windows: card.host.drillWindows }))
            primaryText: card.host.primaryText
            primaryEnabled: card.host.primaryEnabled
            onPrimary: card.host.primaryAction()
        }
    }

    Component { id: displayPanel; DisplayPanel { host: card.host } }
}
