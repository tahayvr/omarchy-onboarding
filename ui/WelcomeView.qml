import QtQuick
import qs.Commons

// The welcome screen: the logo, a short checklist (Wi-Fi, the Omarchy update,
// where every shortcut lives), and the way into the tutorial.
FocusScope {
    id: view

    property var host
    property string logoText: ""
    // From Ui.welcomeChecklist: [{id, done, info, title, detail, action, keys}].
    property var rows: []

    readonly property color secondary: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.62)

    implicitWidth: Style.space(600)
    implicitHeight: column.implicitHeight

    Component.onCompleted: Qt.callLater(function () { yesButton.forceActiveFocus(); })
    Keys.onEscapePressed: view.host.askPause()

    Column {
        id: column
        width: parent.width
        spacing: Style.space(14)

        Text {
            width: parent.width
            text: "Welcome to"
            horizontalAlignment: Text.AlignHCenter
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
        }

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

        Text {
            width: parent.width
            text: "Beautiful, fun & agentic Linux by DHH"
            horizontalAlignment: Text.AlignHCenter
            color: view.secondary
            font.family: Style.font.family
            font.pixelSize: Style.font.body
        }

        Item { width: 1; height: Style.space(4) }

        // --- the checklist
        Column {
            width: parent.width
            spacing: Style.space(8)
            Repeater {
                model: view.rows
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    width: parent.width
                    height: Math.max(texts.implicitHeight, actions.implicitHeight) + Style.space(20)
                    radius: Style.cornerRadius
                    color: Style.normalFill
                    border.width: 1
                    border.color: Style.normalBorderColor

                    // The row's icon: in the accent once done.
                    Text {
                        id: mark
                        anchors { left: parent.left; leftMargin: Style.space(14); verticalCenter: parent.verticalCenter }
                        width: Style.space(32)
                        horizontalAlignment: Text.AlignHCenter
                        text: row.modelData.icon || ""
                        color: row.modelData.done ? Color.accent : Color.foreground
                        font.family: row.modelData.iconFont || Style.font.family
                        font.pixelSize: Style.font.display
                    }

                    Column {
                        id: texts
                        anchors { left: mark.right; leftMargin: Style.space(10); right: actions.left; rightMargin: Style.space(12); verticalCenter: parent.verticalCenter }
                        spacing: Style.space(2)
                        Text {
                            width: parent.width
                            text: row.modelData.title
                            wrapMode: Text.Wrap
                            color: Color.foreground
                            font.family: Style.font.family
                            font.pixelSize: Style.font.title
                        }
                        Text {
                            width: parent.width
                            visible: text !== ""
                            text: row.modelData.detail || ""
                            wrapMode: Text.Wrap
                            color: view.secondary
                            font.family: Style.font.family
                            font.pixelSize: Style.font.bodySmall
                        }
                    }

                    Row {
                        id: actions
                        anchors { right: parent.right; rightMargin: Style.space(12); verticalCenter: parent.verticalCenter }
                        spacing: Style.space(10)
                        KeyCaps {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !!row.modelData.keys && !row.modelData.done
                            keys: row.modelData.keys || ""
                        }
                        Button {
                            visible: row.modelData.action !== ""
                            text: row.modelData.action
                            primary: row.modelData.id !== "keys"
                            onClicked: view.host.checklistAction(row.modelData.id)
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: row.modelData.done
                            text: "✓"
                            color: Color.accent
                            font.family: Style.font.family
                            font.pixelSize: Style.font.heading
                        }
                    }
                }
            }
        }

        // --- the tutorial
        Rectangle {
            width: parent.width
            height: 1
            color: Style.normalBorderColor
        }

        Row {
            width: parent.width
            spacing: Style.space(8)
            Text {
                width: parent.width - noButton.width - yesButton.width - Style.space(16)
                anchors.verticalCenter: parent.verticalCenter
                text: "Want a tutorial on how Omarchy works?"
                wrapMode: Text.Wrap
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.title
            }
            Button { id: noButton; text: "No, exit"; onClicked: view.host.closeWelcome() }
            Button { id: yesButton; text: "Yes"; primary: true; onClicked: view.host.startTutorial() }
        }
    }
}
