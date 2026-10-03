import QtQuick
import QtQuick.Effects
import qs.Commons
import "../omi"
import "../lib/Ui.js" as Ui

// The welcome screen: the logo, a short checklist (Wi-Fi, the Omarchy update,
// where every shortcut lives), and Omi offering the tutorial.
FocusScope {
    id: view

    property var host
    // Omarchy's logo.svg: black on transparent, tinted to the theme's accent.
    property string logoPath: ""
    // From Ui.welcomeChecklist: [{id, done, info, title, detail, action, keys}].
    property var rows: []
    // The checklist's status, {online, update}: Omi's mode comes from it
    // (Ui.welcomeOmi), and so do its reactions (Ui.welcomeOmiReaction).
    property var omiStatus: ({})
    readonly property string omiMode: Ui.welcomeOmi(omiStatus)

    // Omi starts as the plain logo and comes to life once the card is up.
    property bool omiAwake: false
    property var omiBefore: ({})
    onOmiStatusChanged: {
        const reaction = Ui.welcomeOmiReaction(omiBefore, omiStatus);
        omiBefore = omiStatus;
        if (omiAwake && reaction) omi.react(reaction);
    }
    Timer {
        interval: 450
        running: true
        onTriggered: {
            view.omiBefore = view.omiStatus;
            view.omiAwake = true;
        }
    }

    // The update row's button (Update or Try again), which U presses.
    readonly property bool updateAction: rows.some(function (r) { return r.id === "update" && r.action !== ""; })

    readonly property color secondary: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.62)

    implicitWidth: Style.space(600)
    implicitHeight: column.implicitHeight

    Component.onCompleted: Qt.callLater(function () { yesButton.forceActiveFocus(); })
    // On the welcome page Esc is the same as "Exit": no confirmation.
    // Y is "Teach me" and U the update row's button. The buttons only take
    // Return, Enter and Space, so these reach here whichever button has focus.
    Keys.onEscapePressed: view.host.closeWelcome()
    Keys.onPressed: function (event) {
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return;
        if (event.key === Qt.Key_Y) {
            event.accepted = true;
            view.host.startTutorial();
        } else if (event.key === Qt.Key_U && view.updateAction) {
            event.accepted = true;
            view.host.checklistAction("update");
        }
    }

    Column {
        id: column
        width: parent.width
        spacing: Style.space(14)

        // The heading: "Welcome to", the logo and the tagline, kept tight.
        Column {
            width: parent.width
            spacing: Style.space(4)

            Text {
                width: parent.width
                text: "Welcome to"
                horizontalAlignment: Text.AlignHCenter
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.heading
            }

            // Omarchy's own logo.svg, tinted to the theme's accent the way the
            // bar tints symbolic tray icons. It is black, so it is brightened to
            // white first for the colorization to take.
            Item {
                id: logo
                anchors.horizontalCenter: parent.horizontalCenter
                width: Style.space(420)
                height: Math.round(width * 285 / 1215)
                opacity: 0
                scale: 0.96

                Image {
                    id: logoImage
                    anchors.fill: parent
                    source: view.logoPath ? "file://" + view.logoPath : ""
                    fillMode: Image.PreserveAspectFit
                    sourceSize.width: Math.round(width * Screen.devicePixelRatio)
                    sourceSize.height: Math.round(height * Screen.devicePixelRatio)
                    smooth: true
                    visible: false
                    layer.enabled: true
                }

                MultiEffect {
                    anchors.fill: logoImage
                    source: logoImage
                    brightness: 1.0
                    colorization: 1.0
                    colorizationColor: Color.accent
                }

                ParallelAnimation {
                    running: true
                    NumberAnimation { target: logo; property: "opacity"; to: 1; duration: 420; easing.type: Easing.OutCubic }
                    NumberAnimation { target: logo; property: "scale"; to: 1; duration: 520; easing.type: Easing.OutCubic }
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

                    // The row's icon: in the accent once done. Every icon
                    // fills the same square, so they line up across rows.
                    GlyphIcon {
                        id: mark
                        anchors { left: parent.left; leftMargin: Style.space(14); verticalCenter: parent.verticalCenter }
                        size: Style.space(24)
                        glyph: row.modelData.icon || ""
                        family: row.modelData.iconFont || Style.font.family
                        color: row.modelData.done ? Color.accent : Color.foreground
                    }

                    Column {
                        id: texts
                        anchors { left: mark.right; leftMargin: Style.space(14); right: actions.left; rightMargin: Style.space(12); verticalCenter: parent.verticalCenter }
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
                            key: row.modelData.id === "update" ? "U" : ""
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

        // --- the tutorial, set apart from the checklist by space alone
        Item { width: 1; height: Style.space(14) }

        // Omi offers the tour: Omi, what it offers, and the two answers.
        Row {
            width: parent.width
            spacing: Style.space(12)

            // Omi, the Omarchy mascot, in the theme's accent. It starts as the
            // plain logo and comes to life once the card is up.
            Omi {
                id: omi
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(76)
                height: width
                color: Color.accent
                // At this size a bob is a few pixels, and snapped to whole
                // pixels it steps rather than glides; the face still moves.
                bodyMotion: false
                mode: view.omiAwake ? view.omiMode : "mark"
            }

            Column {
                width: parent.width - omi.width - exitButton.width - yesButton.width - Style.space(12) * 2 - Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)
                Text {
                    width: parent.width
                    text: "Hi, I'm Omi"
                    wrapMode: Text.Wrap
                    color: Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.title
                    font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    text: "I can walk you through how Omarchy works."
                    wrapMode: Text.Wrap
                    color: view.secondary
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                }
            }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(8)
                Button { id: yesButton; text: "Teach me"; key: "Y"; primary: true; onClicked: view.host.startTutorial() }
                Button { id: exitButton; text: "Exit"; key: "Esc"; onClicked: view.host.closeWelcome() }
            }
        }
    }
}
