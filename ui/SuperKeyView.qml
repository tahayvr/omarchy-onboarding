import QtQuick
import qs.Commons

// The Super key step: one concept before any drills. Catches a bare Super press, which
// nothing in Omarchy binds, so it reaches this view while it has the keyboard.
FocusScope {
    id: view

    property var host
    property var step: null
    property bool pressed: false

    implicitWidth: Style.space(560)
    implicitHeight: column.implicitHeight
    focus: true

    Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Super_L || event.key === Qt.Key_Super_R || event.key === Qt.Key_Meta) {
            event.accepted = true;
            if (!view.pressed) {
                view.pressed = true;
                view.host.omiReact("success");
                view.host.advanceSoon();
            }
        }
    }
    Keys.onEscapePressed: view.host.askPause()

    Column {
        id: column
        width: parent.width
        spacing: Style.space(20)

        Header { host: view.host; step: view.step }

        Text {
            width: parent.width
            text: view.step ? view.step.screen : ""
            wrapMode: Text.Wrap
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.title
        }

        // The bottom-left corner of a keyboard, with Super picked out.
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(6)
            KeyCap { label: "Ctrl"; big: true }
            KeyCap {
                label: "Super"
                big: true
                lit: view.pressed
                marked: !view.pressed
                SequentialAnimation on scale {
                    running: !view.pressed
                    loops: Animation.Infinite
                    NumberAnimation { to: 1.08; duration: 650; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0; duration: 650; easing.type: Easing.InOutSine }
                }
            }
            KeyCap { label: "Alt"; big: true }
            KeyCap { label: "Space"; big: true; implicitWidth: Style.space(200) }
        }

        Footer { host: view.host }
    }
}
