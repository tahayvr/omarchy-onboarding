import QtQuick
import qs.Commons
import qs.Commons as Commons
import "../lib/Ui.js" as Ui

// A shortcut such as "Super + Shift + Return" as a row of key caps.
Row {
    id: caps

    property string keys: ""
    property bool big: false

    spacing: Style.space(4)

    Repeater {
        model: Ui.keyCapItems(caps.keys)
        delegate: Row {
            required property var modelData
            spacing: Style.space(4)

            Text {
                visible: modelData.plus
                anchors.verticalCenter: parent.verticalCenter
                text: "+"
                color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.62)
                font.family: Style.font.family
                font.pixelSize: Style.font.body
            }
            KeyCap {
                label: modelData.label
                big: caps.big
            }
        }
    }
}
