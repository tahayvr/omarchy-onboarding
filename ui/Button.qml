import QtQuick
import qs.Commons
import qs.Commons as Commons

// A themed button that works with the mouse and the keyboard (Tab, Enter, Space).
// Like Omarchy's own (qs.Ui Button), it has no outline at rest: a faint fill
// marks it, the pointer brightens that, and only keyboard focus draws a border.
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
         : mouse.pressed ? Style.pressedFill
         : mouse.containsMouse || activeFocus ? Style.hoverFill : Style.normalFill
    // Drawn inside the rectangle, so focus doesn't move anything.
    border.width: activeFocus && !primary ? 2 : 0
    border.color: Commons.Color.accent
    Behavior on color { ColorAnimation { duration: Style.duration(120) } }

    // Held down, the button gives a little.
    scale: mouse.pressed ? 0.97 : 1
    Behavior on scale { NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic } }

    // A focused primary button is already the accent: ring it in the
    // foreground instead, inset so it reads on the fill.
    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        visible: button.primary && button.activeFocus
        color: "transparent"
        radius: button.radius
        border.width: 1
        border.color: Qt.rgba(Commons.Color.background.r, Commons.Color.background.g, Commons.Color.background.b, 0.55)
    }

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
