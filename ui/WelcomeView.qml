import QtQuick
import qs.Commons
import "../lib/Ui.js" as Ui

// Step 0: the logo, what's coming, and which track to take.
FocusScope {
    id: view

    property var host
    property string logoText: ""

    property string choice: ""
    property string os: ""
    property bool writesCode: false
    readonly property string track: choice === "switcher" ? os : choice

    implicitWidth: Style.space(560)
    implicitHeight: column.implicitHeight

    Component.onCompleted: Qt.callLater(function () { view.firstChoice.forceActiveFocus(); })

    Column {
        id: column
        width: parent.width
        spacing: Style.space(14)

        // Omarchy's own text logo, revealed line by line in the theme's accent.
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            Repeater {
                model: view.logoText ? view.logoText.replace(/\n+$/, "").split("\n") : []
                delegate: Text {
                    id: logoLine
                    required property string modelData
                    required property int index
                    text: modelData
                    color: Color.accent
                    font.family: Style.font.family
                    font.pixelSize: Math.max(6, Math.round(Style.font.caption * 0.8))
                    opacity: 0
                    Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                    Timer { interval: 40 * index + 1; running: true; onTriggered: logoLine.opacity = 1 }
                }
            }
        }

        Item { width: 1; height: Style.space(4) }

        Text {
            width: parent.width
            text: "Welcome to Omarchy"
            horizontalAlignment: Text.AlignHCenter
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.display
            font.weight: Font.DemiBold
        }
        Text {
            width: parent.width
            text: "About 10 minutes, learning by doing. Every step is skippable, and Esc pauses at any time."
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.62)
            font.family: Style.font.family
            font.pixelSize: Style.font.body
        }

        Item { width: 1; height: Style.space(6) }

        Text {
            text: "How well do you know Linux?"
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.title
        }

        Repeater {
            model: Ui.TRACK_CHOICES
            delegate: Choice {
                required property var modelData
                required property int index
                id: choiceItem
                width: column.width
                title: (view.choice === modelData.id ? "●  " : "○  ") + modelData.label
                detail: modelData.detail
                selected: view.choice === modelData.id
                onPicked: {
                    view.choice = modelData.id;
                    if (modelData.id === "switcher" && !view.os) view.os = "";
                }
                Component.onCompleted: if (index === 0) view.firstChoiceItem = choiceItem
            }
        }

        Row {
            visible: view.choice === "switcher"
            spacing: Style.space(8)
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Coming from"
                color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.62)
                font.family: Style.font.family
                font.pixelSize: Style.font.body
            }
            Button { text: "Mac"; primary: view.os === "mac"; onClicked: view.os = "mac" }
            Button { text: "Windows"; primary: view.os === "windows"; onClicked: view.os = "windows" }
        }

        Choice {
            width: column.width
            title: (view.writesCode ? "■" : "□") + "  I write code"
            detail: "Adds a short section on AI agents and developer setup."
            selected: view.writesCode
            onPicked: view.writesCode = !view.writesCode
        }

        Item { width: 1; height: Style.space(4) }

        Row {
            anchors.right: parent.right
            spacing: Style.space(8)
            Button {
                text: "Later"
                onClicked: view.host.askPause()
            }
            Button {
                text: view.track ? "Start" : (view.choice === "switcher" ? "Pick Mac or Windows" : "Pick one to start")
                primary: view.track !== ""
                opacity: view.track ? 1 : 0.6
                onClicked: if (view.track) view.host.chooseTrack(view.track, view.writesCode)
            }
        }
    }

    property Item firstChoiceItem: null
    readonly property Item firstChoice: firstChoiceItem || view

    Keys.onEscapePressed: view.host.askPause()

    // A selectable row: a title, a line of detail, and a highlight when picked.
    component Choice: Rectangle {
        id: row
        property string title: ""
        property string detail: ""
        property bool selected: false
        signal picked()

        activeFocusOnTab: true
        implicitHeight: texts.implicitHeight + Style.space(18)
        radius: Style.cornerRadius
        color: selected ? Style.selectedAccentFill : mouse.containsMouse || activeFocus ? Style.hoverFill : Style.normalFill
        border.width: activeFocus || selected ? 2 : 1
        border.color: selected || activeFocus ? Color.accent : Style.normalBorderColor

        Keys.onReturnPressed: row.picked()
        Keys.onEnterPressed: row.picked()
        Keys.onSpacePressed: row.picked()

        Column {
            id: texts
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: Style.space(14) }
            spacing: Style.space(2)
            Text {
                text: row.title
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.title
            }
            Text {
                width: parent.width
                text: row.detail
                color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.62)
                wrapMode: Text.Wrap
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
            }
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { row.forceActiveFocus(); row.picked(); }
        }
    }
}
