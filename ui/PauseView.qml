import QtQuick
import qs.Commons

// Esc from any step: keep going, or quit.
FocusScope {
    id: view

    property var host

    // Wide enough for its buttons.
    implicitWidth: Math.max(Style.space(460), pauseButtons.implicitWidth)
    implicitHeight: column.implicitHeight

    Component.onCompleted: Qt.callLater(function () { keepGoing.forceActiveFocus(); })
    Keys.onEscapePressed: view.host.resume()
    // Q, as shown on its button; Esc keeps going.
    Keys.onPressed: function (event) {
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return;
        if (event.key === Qt.Key_Q) { event.accepted = true; view.host.dismiss(); }
    }

    Column {
        id: column
        width: parent.width
        spacing: Style.space(20)

        Row {
            spacing: Style.space(14)
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
            text: "If you quit, run omarchy onboarding any time to come back to it."
            wrapMode: Text.Wrap
            color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.62)
            font.family: Style.font.family
            font.pixelSize: Style.font.body
        }
        Row {
            id: pauseButtons
            anchors.right: parent.right
            spacing: Style.space(10)
            Button { text: "Quit onboarding"; key: "Q"; onClicked: view.host.dismiss() }
            Button { id: keepGoing; text: "Keep going"; key: "Esc"; primary: true; onClicked: view.host.resume() }
        }
    }
}
