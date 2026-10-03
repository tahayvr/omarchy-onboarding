import QtQuick
import qs.Commons

// The tutorial's progress as a line along the card's top border: its length
// is how far through the tutorial you are. Hidden when `progress` is below 0.
Rectangle {
    id: line

    property real progress: -1

    anchors { top: parent.top; left: parent.left }
    visible: progress >= 0
    width: parent.width * Math.max(0, Math.min(1, progress))
    height: Math.max(3, Style.space(5))
    color: Color.accent
    z: 10

    Behavior on width { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
}
