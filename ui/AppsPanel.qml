import QtQuick
import qs.Commons

// Step 13: the everyday apps as bound on this machine, each with its keys.
Column {
    id: panel
    property var host
    spacing: Style.space(8)

    Line {
        visible: panel.host.apps.length === 0
        secondary: true
        text: "I couldn't read your app shortcuts, but Super + K lists them all."
    }

    Repeater {
        model: panel.host.apps
        delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property bool tried: !!panel.host.appsTried[modelData.label]
            width: panel.width
            implicitHeight: Math.max(caps.implicitHeight, tryButton.implicitHeight)

            Line {
                anchors { left: parent.left; right: caps.left; rightMargin: Style.space(8); verticalCenter: parent.verticalCenter }
                width: undefined
                text: (row.tried ? "✓  " : "") + row.modelData.label
            }
            KeyCaps {
                id: caps
                anchors { right: tryButton.left; rightMargin: Style.space(8); verticalCenter: parent.verticalCenter }
                keys: row.modelData.keys
            }
            Button {
                id: tryButton
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: "Try it"
                onClicked: panel.host.tryApp(row.modelData)
            }
        }
    }
}
