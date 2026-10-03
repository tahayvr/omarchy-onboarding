import QtQuick
import qs.Commons

// One sub-task of a drill: a tick, what to do, and its keys.
Item {
    id: row

    property string label: ""
    property string keys: ""
    property bool done: false
    property bool big: false

    implicitHeight: Math.max(line.implicitHeight, caps.implicitHeight)
    // How wide the key caps are, so the card can make room for them.
    readonly property real capsWidth: caps.implicitWidth

    Text {
        id: mark
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        width: Style.space(20)
        text: row.done ? "✓" : "○"
        color: row.done ? Color.accent : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.62)
        font.family: Style.font.family
        font.pixelSize: Style.font.title
    }

    Text {
        id: line
        anchors { left: mark.right; right: caps.left; rightMargin: Style.space(12); verticalCenter: parent.verticalCenter }
        text: row.label
        color: row.done ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.62) : Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.strikeout: false
        wrapMode: Text.Wrap
    }

    KeyCaps {
        id: caps
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        keys: row.keys
        big: row.big && !row.done
        opacity: row.done ? 0.45 : 1
    }
}
