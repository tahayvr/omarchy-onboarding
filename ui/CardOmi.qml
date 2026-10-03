import QtQuick
import qs.Commons
import "../omi"
import "../lib/Ui.js" as Ui

// Omi on a card, speaking its text: the overlay's omiMode, with a short
// reaction when the overlay calls omiReact(). Small, so no whole-body motion:
// a bob a few pixels high steps instead of gliding once snapped to pixels.
Omi {
    id: omi

    property var host

    // The size asked for; drawn at the next even size up (Ui.evenOmiSize).
    property real size: Style.space(48)
    width: Ui.evenOmiSize(size, dpr)
    height: width
    color: Color.accent
    bodyMotion: false
    mode: host ? host.omiMode : "idle"
    look: host && host.omiLook ? host.omiLook : [0, 0]

    Connections {
        target: omi.host
        function onOmiReacted(reaction) { omi.react(reaction, 1.2); }
    }
}
