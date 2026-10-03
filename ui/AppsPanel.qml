import QtQuick
import qs.Commons

// Step 13: the everyday apps as bound on this machine, each with its keys.
// An app ticks when its window or panel opens (the overlay watches for it),
// so the shortcut beside it is the way to try it.
Column {
    id: panel
    property var host
    spacing: Style.space(12)

    // The widest key caps, so the card can make room for them (CoachCard).
    property real capsNeed: 0
    function measure() {
        var m = 0;
        for (var i = 0; i < rows.count; i++) {
            var it = rows.itemAt(i);
            if (it) m = Math.max(m, it.capsWidth);
        }
        capsNeed = m;
    }

    Row {
        visible: panel.host.apps.length === 0
        width: panel.width
        spacing: Style.space(8)
        Line {
            width: parent.width - listCaps.width - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            secondary: true
            text: "I couldn't read your app shortcuts, but the full list has them all."
        }
        KeyCaps { id: listCaps; anchors.verticalCenter: parent.verticalCenter; keys: "Super + K" }
    }

    Repeater {
        id: rows
        model: panel.host.apps
        onCountChanged: panel.measure()
        onItemAdded: panel.measure()
        delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property bool tried: !!panel.host.appsTried[modelData.label]
            readonly property real capsWidth: caps.implicitWidth
            width: panel.width
            implicitHeight: Math.max(caps.implicitHeight, mark.implicitHeight)

            Text {
                id: mark
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                width: Style.space(20)
                text: row.tried ? "✓" : "○"
                color: row.tried ? Color.accent : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.62)
                font.family: Style.font.family
                font.pixelSize: Style.font.title
            }
            Line {
                anchors { left: mark.right; right: caps.left; rightMargin: Style.space(12); verticalCenter: parent.verticalCenter }
                width: undefined
                text: row.modelData.label
                color: row.tried ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.62) : Color.foreground
            }
            KeyCaps {
                id: caps
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                keys: row.modelData.keys
                opacity: row.tried ? 0.45 : 1
            }
        }
    }
}
