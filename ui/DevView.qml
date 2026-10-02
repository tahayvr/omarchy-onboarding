import QtQuick
import qs.Commons
import "../lib/Ui.js" as Ui

// Step 15: git identity, an SSH key, and the editor. Each part is optional;
// Continue is always there.
FocusScope {
    id: view

    property var host
    property var step: null
    property var info: ({})
    property var ticked: ({})
    property string publicKey: ""

    readonly property bool hasKey: (info.keys || []).length > 0 || publicKey !== ""
    readonly property bool emailOk: Ui.validEmail(emailField.text)
    readonly property bool gitUnchanged: !!info.gitSet && nameField.text.trim() === (info.name || "") && emailField.text.trim() === (info.email || "")

    implicitWidth: Style.space(620)
    implicitHeight: column.implicitHeight

    Component.onCompleted: Qt.callLater(function () { nameField.forceActiveFocus(); })
    Keys.onEscapePressed: view.host.askPause()

    Column {
        id: column
        width: parent.width
        spacing: Style.space(14)

        Header { host: view.host; step: view.step }

        // --- git
        Section { title: "Git"; done: !!view.ticked.git }
        Row {
            width: parent.width
            spacing: Style.space(8)
            Field { id: nameField; width: (parent.width - Style.space(8)) / 2; placeholder: "Full name"; initial: view.info.name || "" }
            Field { id: emailField; width: (parent.width - Style.space(8)) / 2; placeholder: "Email"; initial: view.info.email || "" }
        }
        Row {
            spacing: Style.space(8)
            Button {
                text: view.ticked.git && view.gitUnchanged ? "Saved" : view.gitUnchanged ? "Keep these" : "Save to git"
                enabled: nameField.text.trim() !== "" && view.emailOk
                opacity: enabled ? 1 : 0.5
                onClicked: view.host.saveGit(nameField.text, emailField.text, view.gitUnchanged)
            }
            Line {
                width: implicitWidth
                anchors.verticalCenter: parent.verticalCenter
                visible: emailField.text !== "" && !view.emailOk
                secondary: true
                text: "That email doesn't look right."
            }
        }

        // --- ssh
        Section { title: "SSH key"; done: !!view.ticked.ssh }
        Line {
            secondary: true
            text: view.hasKey ? "Add this public key to GitHub (Settings › SSH keys) or a server. Select it and press Super + C, or use Copy."
                              : "No SSH key yet. One key works for GitHub, GitLab and your servers."
        }
        Rectangle {
            visible: view.publicKey !== ""
            width: parent.width
            height: keyText.implicitHeight + Style.space(14)
            radius: Style.cornerRadius
            color: Style.normalFill
            border.width: keyText.activeFocus ? 2 : 1
            border.color: keyText.activeFocus ? Color.accent : Style.normalBorderColor
            TextEdit {
                id: keyText
                anchors { fill: parent; margins: Style.space(7) }
                text: view.publicKey
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.WrapAnywhere
                color: Color.foreground
                selectionColor: Style.selectionFill
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
            }
        }
        Row {
            spacing: Style.space(8)
            Button { visible: !view.hasKey; text: "Create an SSH key"; onClicked: view.host.createSshKey(emailField.text) }
            Button { visible: view.publicKey !== ""; text: "Copy public key"; onClicked: view.host.copyPublicKey() }
        }

        // --- editor
        Section { title: "Editor"; done: !!view.ticked.editor }
        Row {
            spacing: Style.space(10)
            KeyCaps { anchors.verticalCenter: parent.verticalCenter; keys: "Super + Shift + N" }
            Button { text: "Open it"; onClicked: view.host.openEditor() }
        }
        Line { secondary: true; text: Ui.editorTip(view.info.editor) }

        Row {
            anchors.right: parent.right
            spacing: Style.space(8)
            Button { text: "Skip"; onClicked: view.host.skip() }
            Button { text: "Continue"; primary: true; onClicked: view.host.next() }
        }
    }

    component Section: Row {
        property string title: ""
        property bool done: false
        spacing: Style.space(8)
        Text {
            text: parent.done ? "✓" : "○"
            color: parent.done ? Color.accent : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.62)
            font.family: Style.font.family
            font.pixelSize: Style.font.title
        }
        Text {
            text: parent.title
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.weight: Font.DemiBold
        }
    }

    // A text field that starts from `initial` until the user types.
    component Field: Rectangle {
        id: field
        property string placeholder: ""
        property string initial: ""
        property alias text: input.text
        activeFocusOnTab: true
        height: input.implicitHeight + Style.space(16)
        radius: Style.cornerRadius
        color: Style.normalFill
        border.width: input.activeFocus ? 2 : 1
        border.color: input.activeFocus ? Color.accent : Style.normalBorderColor
        onActiveFocusChanged: if (activeFocus) input.forceActiveFocus()
        onInitialChanged: if (!input.edited) input.text = initial

        TextInput {
            id: input
            property bool edited: false
            anchors { fill: parent; margins: Style.space(8) }
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            color: Color.foreground
            selectionColor: Style.selectionFill
            selectByMouse: true
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            onTextEdited: edited = true
            KeyNavigation.tab: field.KeyNavigation.tab
            Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                visible: !input.text
                text: field.placeholder
                color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.45)
                font: input.font
            }
        }
    }
}
