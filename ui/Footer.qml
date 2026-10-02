import QtQuick
import qs.Commons

// Skip, and after 40 s without progress, "Do it for me".
Item {
    id: footer

    property var host
    property int hint: 0
    property bool canDoIt: false
    // What to say after 20 s without progress; views with their own hint pass "".
    property string idleText: "Take your time. The keys are on the right."
    // An optional main button, e.g. "Looks right" or "Continue".
    property string primaryText: ""
    property bool primaryEnabled: true
    signal primary()

    width: parent ? parent.width : implicitWidth
    implicitHeight: buttons.implicitHeight

    Text {
        anchors { left: parent.left; right: buttons.left; rightMargin: Style.space(8); verticalCenter: parent.verticalCenter }
        visible: footer.hint > 1 ? footer.canDoIt : (footer.hint > 0 && footer.idleText !== "")
        text: footer.hint > 1 ? "Stuck? I can do it." : footer.idleText
        elide: Text.ElideRight
        color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.62)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
    }

    Row {
        id: buttons
        anchors.right: parent.right
        spacing: Style.space(8)
        Button { text: "Skip"; onClicked: footer.host.skip() }
        Button {
            visible: footer.canDoIt && footer.hint > 1
            text: "Do it for me"
            primary: footer.primaryText === ""
            onClicked: footer.host.doIt()
        }
        Button {
            visible: footer.primaryText !== ""
            text: footer.primaryText
            primary: footer.primaryEnabled
            opacity: footer.primaryEnabled ? 1 : 0.5
            onClicked: if (footer.primaryEnabled) footer.primary()
        }
    }
}
