import QtQuick
import qs.Commons

// Back, Skip, and after a minute without progress, "Do it for me". While the
// tutorial's keys are bound, "Ctrl + key" is said once here, at the left,
// and each button carries only its key. What Omi says when the user
// stalls is in the header (Ui.omiHint), not here.
Item {
    id: footer

    property var host
    property int hint: 0
    property bool canDoIt: false
    // An optional main button, e.g. "Looks right" or "Continue".
    property string primaryText: ""
    property bool primaryEnabled: true
    signal primary()

    readonly property bool legendShown: !!host && Object.keys(host.tutorialKeys).length > 0

    width: parent ? parent.width : implicitWidth
    // The buttons and the legend: a card never gets narrower than this row.
    implicitWidth: buttons.implicitWidth + (legendShown ? legend.implicitWidth + Style.space(16) : 0)
    implicitHeight: buttons.implicitHeight

    // Every key on this card is Ctrl + what its chip shows.
    Text {
        id: legend
        visible: footer.legendShown
        anchors { left: parent.left; verticalCenter: buttons.verticalCenter }
        text: "Ctrl + key"
        color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.62)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
    }

    Row {
        id: buttons
        anchors { right: parent.right; bottom: parent.bottom }
        spacing: Style.space(8)
        Button { visible: footer.host.canBack; text: "Back"; key: footer.host.tutorialKeys.back || ""; onClicked: footer.host.back() }
        Button { text: "Skip"; key: footer.host.tutorialKeys.skip || ""; onClicked: footer.host.skip() }
        Button {
            visible: footer.canDoIt && footer.hint > 1
            text: "Do it for me"
            key: footer.host.tutorialKeys.doit || ""
            primary: footer.primaryText === ""
            onClicked: footer.host.doIt()
        }
        Button {
            visible: footer.primaryText !== ""
            text: footer.primaryText
            key: footer.host.tutorialKeys.primary || ""
            primary: footer.primaryEnabled
            opacity: footer.primaryEnabled ? 1 : 0.5
            onClicked: if (footer.primaryEnabled) footer.primary()
        }
    }
}
