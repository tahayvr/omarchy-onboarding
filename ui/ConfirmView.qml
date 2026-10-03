import QtQuick
import qs.Commons

// Asks before anything that changes the system (spec ground rule). Centered,
// so it has the keyboard: Enter confirms, Esc cancels.
FocusScope {
    id: view

    property var host
    property string question: ""
    property string confirmText: "Go ahead"

    implicitWidth: Style.space(480)
    implicitHeight: column.implicitHeight

    Component.onCompleted: Qt.callLater(function () { yes.forceActiveFocus(); })
    Keys.onEscapePressed: view.host.answerConfirm(false)
    // Enter confirms wherever the focus is (Tab can move it to Not now, which
    // takes Enter itself).
    Keys.onReturnPressed: view.host.answerConfirm(true)
    Keys.onEnterPressed: view.host.answerConfirm(true)

    Column {
        id: column
        width: parent.width
        spacing: Style.space(16)

        Row {
            width: parent.width
            spacing: Style.space(10)
            CardOmi { id: omi; host: view.host; anchors.verticalCenter: parent.verticalCenter }
            Text {
                width: parent.width - omi.width - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                text: view.question
                wrapMode: Text.Wrap
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.title
            }
        }
        Text {
            visible: view.host.dryRun
            text: "Dry run: this will only be logged."
            color: Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
        }
        Row {
            anchors.right: parent.right
            spacing: Style.space(8)
            Button { text: "Not now"; key: "Esc"; onClicked: view.host.answerConfirm(false) }
            Button { id: yes; text: view.confirmText; key: "\u21b5"; primary: true; onClicked: view.host.answerConfirm(true) }
        }
    }
}
