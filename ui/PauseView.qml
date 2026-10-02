import QtQuick
import qs.Commons

// Esc from any step: keep going, pause until the next login, or quit.
FocusScope {
    id: view

    property var host

    implicitWidth: Style.space(460)
    implicitHeight: column.implicitHeight

    Component.onCompleted: Qt.callLater(function () { keepGoing.forceActiveFocus(); })
    Keys.onEscapePressed: view.host.resume()

    Column {
        id: column
        width: parent.width
        spacing: Style.space(14)

        Text {
            text: "Pause or quit onboarding?"
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.weight: Font.DemiBold
        }
        Text {
            width: parent.width
            text: "Remind me later shows one notification at your next login. Either way, omarchy onboarding brings it back."
            wrapMode: Text.Wrap
            color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.62)
            font.family: Style.font.family
            font.pixelSize: Style.font.body
        }
        Row {
            anchors.right: parent.right
            spacing: Style.space(8)
            Button { text: "Quit onboarding"; onClicked: view.host.dismiss() }
            Button { text: "Remind me later"; onClicked: view.host.pause() }
            Button { id: keepGoing; text: "Keep going"; primary: true; onClicked: view.host.resume() }
        }
    }
}
