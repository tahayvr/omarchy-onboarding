import QtQuick
import qs.Commons
import "../lib/Ui.js" as Ui

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
    // M opens the step's link (the manual) and D does the steps still to
    // do, as shown on their buttons.
    Keys.onPressed: function (event) {
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return;
        if (event.key === Qt.Key_M && view.step && view.step.link) { event.accepted = true; view.host.openLink(); }
        else if (event.key === Qt.Key_D && view.finishing && view.openSteps.length > 0) { event.accepted = true; view.host.redoOpen(); }
    }

    // Commands in the card's text sit on a faint chip, so they read as
    // something to type (Ui.richCode).
    readonly property color codeFill: Qt.rgba(
        Color.popups.background.r * 0.86 + Color.foreground.r * 0.14,
        Color.popups.background.g * 0.86 + Color.foreground.g * 0.14,
        Color.popups.background.b * 0.86 + Color.foreground.b * 0.14, 1)

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
                key: "M"
                onClicked: view.host.openLink()
            }
        }

        // The steps still to do (skipped, deferred or failed), and a way
        // through them: only they are shown, then the finish screen again.
        Item {
            visible: view.finishing && view.openSteps.length > 0
            width: parent.width
            implicitHeight: Math.max(openList.implicitHeight, redoButton.implicitHeight)
            Column {
                id: openList
                anchors { left: parent.left; right: redoButton.left; rightMargin: Style.space(12); top: parent.top }
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
                        width: openList.width
                        text: "○  " + modelData.title + (modelData.reason ? " (" + modelData.reason + ")" : "")
                        wrapMode: Text.Wrap
                        color: Color.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                    }
                }
            }
            Button {
                id: redoButton
                anchors { right: parent.right; top: parent.top }
                text: view.openSteps.length === 1 ? "Do it now" : "Do them now"
                key: "D"
                onClicked: view.host.redoOpen()
            }
        }

        // The card's last line (the finish screen's way back in).
        Text {
            width: parent.width
            visible: text !== ""
            textFormat: Text.RichText
            text: view.step && view.step.outro ? Ui.richCode(view.step.outro, view.codeFill.toString()) : ""
            wrapMode: Text.Wrap
            color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.62)
            font.family: Style.font.family
            font.pixelSize: Style.font.body
        }

        Row {
            anchors.right: parent.right
            spacing: Style.space(8)
            Button { visible: !view.finishing; text: "Skip"; onClicked: view.host.skip() }
            Button {
                id: primary
                text: view.finishing ? "Finish" : "Continue"
                key: "Enter"
                primary: true
                onClicked: view.host.next()
            }
        }
    }
}
