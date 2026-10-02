import QtQuick
import qs.Commons
import "../lib/Ui.js" as Ui

// Step 14: the agents Omarchy pre-wires. Choosing one asks first, because
// Omarchy installs it if needed and opens it to sign in.
FocusScope {
    id: view

    property var host
    property var step: null
    property var agents: []
    property string waitingFor: ""

    readonly property var current: agents.filter(function (a) { return a.current; })[0] || null
    readonly property var selected: agents.length ? agents[Math.max(0, Math.min(list.currentIndex, agents.length - 1))] : null

    implicitWidth: Style.space(600)
    implicitHeight: column.implicitHeight

    Component.onCompleted: Qt.callLater(function () { list.forceActiveFocus(); })
    Keys.onEscapePressed: view.host.askPause()

    Column {
        id: column
        width: parent.width
        spacing: Style.space(14)

        Header { host: view.host; step: view.step }

        Line {
            text: view.waitingFor
                ? "Installing and opening " + view.waitingFor + ". Sign in in its window; this moves on once it's set."
                : (view.step ? view.step.screen : "")
            color: view.waitingFor ? Color.accent : Color.foreground
        }
        Line {
            visible: view.current !== null && !view.waitingFor
            secondary: true
            text: view.current ? "Your default right now is " + view.current.label + "." : ""
        }

        ListView {
            id: list
            width: parent.width
            height: Math.min(Style.space(380), contentHeight)
            clip: true
            focus: true
            spacing: Style.space(4)
            model: view.agents
            currentIndex: Math.max(0, view.agents.findIndex(function (a) { return a.current; }))
            keyNavigationEnabled: true
            Keys.onReturnPressed: view.host.chooseAgent(view.selected ? view.selected.name : "")
            Keys.onEnterPressed: view.host.chooseAgent(view.selected ? view.selected.name : "")

            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property bool selected: ListView.isCurrentItem
                width: list.width
                height: texts.implicitHeight + Style.space(14)
                radius: Style.cornerRadius
                color: selected ? Style.selectedAccentFill : Style.normalFill
                border.width: selected ? 2 : 1
                border.color: selected ? Color.accent : Style.normalBorderColor

                Column {
                    id: texts
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: Style.space(12) }
                    Text {
                        text: row.modelData.label + (row.modelData.current ? "  ·  current" : "")
                        color: Color.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                    }
                    Text {
                        visible: text !== ""
                        width: parent.width
                        text: Ui.agentNote(row.modelData.name)
                        elide: Text.ElideRight
                        color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.62)
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { list.currentIndex = row.index; list.forceActiveFocus(); }
                    onDoubleClicked: view.host.chooseAgent(row.modelData.name)
                }
            }
        }

        Row {
            anchors.right: parent.right
            spacing: Style.space(8)
            Button { text: "Skip"; onClicked: view.host.skip() }
            Button {
                visible: view.current !== null && !(view.selected && view.selected.current)
                text: "Keep " + (view.current ? view.current.label : "")
                onClicked: view.host.keepAgent()
            }
            Button {
                text: !view.selected ? "Use" : view.selected.current ? "Keep " + view.selected.label : "Use " + view.selected.label
                primary: true
                enabled: !view.waitingFor
                opacity: enabled ? 1 : 0.5
                onClicked: view.host.chooseAgent(view.selected ? view.selected.name : "")
            }
        }
    }
}
