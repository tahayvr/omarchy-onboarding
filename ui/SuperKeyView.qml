import QtQuick
import qs.Commons

// Step 3: one concept before any drills. Catches a bare Super press, which
// nothing in Omarchy binds, so it reaches this view while it has the keyboard.
FocusScope {
    id: view

    property var host
    property var step: null
    property int hint: 0
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
                done.start();
            }
        }
    }
    Keys.onEscapePressed: view.host.askPause()

    // Let the user see the key light up before moving on.
    Timer { id: done; interval: 700; onTriggered: view.host.next() }

    Column {
        id: column
        width: parent.width
        spacing: Style.space(16)

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
                id: superCap
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

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: view.pressed ? "That's the one!" : view.hint > 0 ? "Look on the bottom row, left of the space bar, next to Alt." : ""
            color: view.pressed ? Color.accent : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.62)
            font.family: Style.font.family
            font.pixelSize: Style.font.body
        }

        Footer { host: view.host; hint: view.hint; canDoIt: true; idleText: "" }
    }
}
