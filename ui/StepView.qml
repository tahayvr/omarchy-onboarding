import QtQuick
import qs.Commons

// A centered step without its own screen yet (the action steps arrive in M4),
// and the finish screen.
FocusScope {
    id: view

    property var host
    property var step: null
    property var openSteps: []

    readonly property bool finishing: step && step.id === "finish"

    implicitWidth: Style.space(520)
    implicitHeight: column.implicitHeight

    Component.onCompleted: Qt.callLater(function () { primary.forceActiveFocus(); })
    // On the finish screen Esc is the same as Finish.
    Keys.onEscapePressed: view.finishing ? view.host.next() : view.host.askPause()

    Column {
        id: column
        width: parent.width
        spacing: Style.space(14)

        Header { host: view.host; step: view.step; omiSize: view.finishing ? Style.space(96) : Style.space(48) }

        Text {
            width: parent.width
            visible: text !== ""
            text: view.step ? (view.step.screen || view.step.goal || "") : ""
            wrapMode: Text.Wrap
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.title
        }

        // Keys worth remembering (the finish screen's `remember`).
        Column {
            visible: !!(view.step && view.step.remember)
            width: parent.width
            spacing: Style.space(8)
            Repeater {
                model: view.step && view.step.remember ? view.step.remember : []
                delegate: Item {
                    required property var modelData
                    width: parent.width
                    implicitHeight: Math.max(rememberCaps.implicitHeight, rememberLabel.implicitHeight)
                    Text {
                        id: rememberLabel
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.label
                        color: Color.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                    }
                    KeyCaps {
                        id: rememberCaps
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        keys: modelData.keys
                    }
                }
            }
        }

        // A page to read next (the manual), as Omi's line and a button.
        Item {
            visible: !!(view.step && view.step.link)
            width: parent.width
            implicitHeight: Math.max(linkText.implicitHeight, linkButton.implicitHeight)
            Text {
                id: linkText
                anchors { left: parent.left; right: linkButton.left; rightMargin: Style.space(12); verticalCenter: parent.verticalCenter }
                text: view.step && view.step.link ? view.step.link.text : ""
                wrapMode: Text.Wrap
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
            }
            Button {
                id: linkButton
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: view.step && view.step.link ? view.step.link.label : ""
                onClicked: view.host.openLink()
            }
        }

        Column {
            visible: view.finishing && view.openSteps.length > 0
            width: parent.width
            spacing: Style.space(4)
            Text {
                text: "Still to do"
                color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.62)
                font.family: Style.font.family
                font.pixelSize: Style.font.body
            }
            Repeater {
                model: view.finishing ? view.openSteps : []
                delegate: Text {
                    required property var modelData
                    text: "○  " + modelData.title + (modelData.reason ? " (" + modelData.reason + ")" : "")
                    color: Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                }
            }
        }

        Row {
            anchors.right: parent.right
            spacing: Style.space(8)
            Button { visible: !view.finishing; text: "Skip"; onClicked: view.host.skip() }
            Button {
                id: primary
                text: view.finishing ? "Finish" : "Continue"
                primary: true
                onClicked: view.host.next()
            }
        }
    }
}
