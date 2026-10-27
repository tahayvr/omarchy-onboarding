import QtQuick
import qs.Commons
import qs.Commons as Commons

// A themed button that works with the mouse and the keyboard (Tab, Enter, Space).
Rectangle {
    id: button

    property string text: ""
    property bool primary: false
    // A key that does the same, drawn as a small cap after the label.
    property string key: ""
    signal clicked()

    activeFocusOnTab: true
    implicitWidth: content.implicitWidth + Style.space(32)
    implicitHeight: label.implicitHeight + Style.space(16)
    radius: Style.cornerRadius
    color: primary ? Commons.Color.accent
         : mouse.containsMouse || activeFocus ? Style.hoverFill : Style.normalFill
    border.width: activeFocus ? 2 : 1
    border.color: activeFocus ? Commons.Color.accent
                : primary ? Commons.Color.accent : Style.normalBorderColor

    Keys.onReturnPressed: button.clicked()
    Keys.onEnterPressed: button.clicked()
    Keys.onSpacePressed: button.clicked()

    readonly property color ink: primary ? Commons.Color.background : Commons.Color.foreground

    Row {
        id: content
        anchors.centerIn: parent
        spacing: Style.space(8)

        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            text: button.text
            color: button.ink
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.weight: button.primary ? Font.DemiBold : Font.Normal
        }

        KeyChip {
            anchors.verticalCenter: parent.verticalCenter
            key: button.key
            onAccent: button.primary
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }
}
