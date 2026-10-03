import QtQuick
import qs.Commons

// Esc from any step: keep going, pause until the next login, or quit.
FocusScope {
    id: view

    property var host

    // Wide enough for its three buttons.
    implicitWidth: Math.max(Style.space(460), pauseButtons.implicitWidth)
    implicitHeight: column.implicitHeight

    Component.onCompleted: Qt.callLater(function () { keepGoing.forceActiveFocus(); })
    Keys.onEscapePressed: view.host.resume()
    // R and Q, as shown on their buttons; Esc keeps going.
    Keys.onPressed: function (event) {
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return;
        if (event.key === Qt.Key_R) { event.accepted = true; view.host.pause(); }
        else if (event.key === Qt.Key_Q) { event.accepted = true; view.host.dismiss(); }
    }

    Column {
        id: column
        width: parent.width
        spacing: Style.space(14)

        Row {
            spacing: Style.space(10)
            CardOmi { host: view.host; anchors.verticalCenter: parent.verticalCenter }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Taking a break?"
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.heading
                font.weight: Font.DemiBold
            }
        }
        Text {
            width: parent.width
            text: "Pick Remind me later and I'll nudge you once at your next login."
            wrapMode: Text.Wrap
            color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.62)
            font.family: Style.font.family
            font.pixelSize: Style.font.body
        }
        Row {
            id: pauseButtons
            anchors.right: parent.right
            spacing: Style.space(8)
            Button { text: "Quit onboarding"; key: "Q"; onClicked: view.host.dismiss() }
            Button { text: "Remind me later"; key: "R"; onClicked: view.host.pause() }
            Button { id: keepGoing; text: "Keep going"; key: "Esc"; primary: true; onClicked: view.host.resume() }
        }
    }
}
