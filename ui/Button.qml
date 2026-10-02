import QtQuick
import qs.Commons

// A themed button that works with the mouse and the keyboard (Tab, Enter, Space).
Rectangle {
    id: button

    property string text: ""
    property bool primary: false
    signal clicked()

    activeFocusOnTab: true
    implicitWidth: label.implicitWidth + Style.space(28)
    implicitHeight: label.implicitHeight + Style.space(14)
    radius: Style.cornerRadius
    color: primary ? Color.accent
         : mouse.containsMouse || activeFocus ? Style.hoverFill : Style.normalFill
    border.width: activeFocus ? 2 : 1
    border.color: activeFocus ? Color.accent
                : primary ? Color.accent : Style.normalBorderColor

    Keys.onReturnPressed: button.clicked()
    Keys.onEnterPressed: button.clicked()
    Keys.onSpacePressed: button.clicked()

    Text {
        id: label
        anchors.centerIn: parent
        text: button.text
        color: button.primary ? Color.background : Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.weight: button.primary ? Font.DemiBold : Font.Normal
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }
}
