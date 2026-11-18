import QtQuick
import qs.Commons
import qs.Commons as Commons
import "../lib/Ui.js" as Ui

// Back, Skip, and after a minute without progress, "Do it for me". While the
// tutorial's keys are bound, each button's chip shows its whole chord
// (Ctrl + /). What Omi says when the user stalls is in the header
// (Ui.omiHint), not here.
Item {
    id: footer

    property var host
    // An optional main button: "Looks right" or "Keep my theme".
    property string primaryText: ""
    signal primary()

    width: parent ? parent.width : implicitWidth
    // A card never gets narrower than its buttons.
    implicitWidth: buttons.implicitWidth
    // Room above the buttons: the footer sits apart from the content.
    implicitHeight: buttons.implicitHeight + Style.space(8)

    Row {
        id: buttons
        anchors { right: parent.right; bottom: parent.bottom }
        spacing: Style.space(10)
        Button { visible: footer.host.canBack; text: "Back"; key: Ui.tutorialChord(footer.host.tutorialKeys.back); onClicked: footer.host.back() }
        Button { text: "Skip"; key: Ui.tutorialChord(footer.host.tutorialKeys.skip); onClicked: footer.host.skip() }
        Button {
            visible: footer.host.canDoIt
            text: "Do it for me"
            key: Ui.tutorialChord(footer.host.tutorialKeys.doit)
            primary: footer.primaryText === ""
            onClicked: footer.host.doIt()
        }
        Button {
            visible: footer.primaryText !== ""
            text: footer.primaryText
            key: Ui.tutorialChord(footer.host.tutorialKeys.primary)
            primary: true
            onClicked: footer.primary()
        }
    }
}
