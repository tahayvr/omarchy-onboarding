import QtQuick
import qs.Commons

// A themed button that works with the mouse and the keyboard (Tab, Enter, Space).
Rectangle {
    id: button

    property string text: ""
    property bool primary: false
    // A key that does the same, drawn as a small cap after the label.
    property string key: ""
    signal clicked()

    activeFocusOnTab: true
    implicitWidth: content.implicitWidth + Style.space(28)
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

    readonly property color ink: primary ? Color.background : Color.foreground

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

        // A muted chip, not a second button: the theme's background showing
        // through faintly on the accent fill, the foreground faintly on the
        // plain one. No border, so it doesn't echo the button's own outline.
        Rectangle {
            visible: button.key !== ""
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: Math.max(implicitHeight, keyLabel.implicitWidth + Style.space(8))
            implicitHeight: keyLabel.implicitHeight + Style.space(4)
            radius: Math.max(Style.cornerRadius, Style.space(3))
            color: button.primary ? Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.22)
                                  : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1)

            Text {
                id: keyLabel
                anchors.centerIn: parent
                text: button.key
                color: Qt.rgba(button.ink.r, button.ink.g, button.ink.b, 0.6)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.weight: Font.Normal
            }
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
