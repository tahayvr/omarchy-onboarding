import QtQuick
import qs.Commons

// Step 10: every theme as a preview. Arrows move, Enter applies (the explicit
// confirmation), and the whole desktop restyles behind this card.
FocusScope {
    id: view

    property var host
    property var step: null
    property var themes: []
    property bool applying: false
    property string applied: ""

    readonly property int columns: 4
    readonly property var current: themes.length ? themes[Math.max(0, Math.min(grid.currentIndex, themes.length - 1))] : null

    implicitWidth: Style.space(860)
    implicitHeight: column.implicitHeight

    Component.onCompleted: Qt.callLater(function () { grid.forceActiveFocus(); })
    Keys.onEscapePressed: view.host.askPause()

    Column {
        id: column
        width: parent.width
        spacing: Style.space(14)

        Header { host: view.host; step: view.step }

        Text {
            width: parent.width
            text: view.applied
                ? "Applied. Super + Ctrl + Space cycles this theme's backgrounds, and Super + Ctrl + Shift + Space brings this picker back any time."
                : (view.step ? view.step.screen : "")
            wrapMode: Text.Wrap
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
        }

        GridView {
            id: grid
            width: parent.width
            height: Math.min(Style.space(470), Math.ceil(view.themes.length / view.columns) * cellHeight)
            cellWidth: Math.floor(width / view.columns)
            cellHeight: Math.round(cellWidth * 0.62)
            clip: true
            focus: true
            model: view.themes
            keyNavigationEnabled: true
            highlightFollowsCurrentItem: true
            currentIndex: Math.max(0, view.themes.findIndex(function (t) { return t.current; }))
            onCountChanged: Qt.callLater(function () { grid.positionViewAtIndex(grid.currentIndex, GridView.Center); })

            Keys.onReturnPressed: view.host.applyTheme(view.current)
            Keys.onEnterPressed: view.host.applyTheme(view.current)

            delegate: Item {
                id: cell
                required property var modelData
                required property int index
                readonly property bool selected: GridView.isCurrentItem
                width: grid.cellWidth
                height: grid.cellHeight

                Rectangle {
                    anchors { fill: parent; margins: Style.space(5) }
                    radius: Style.cornerRadius
                    color: Style.normalFill
                    border.width: cell.selected ? 3 : 1
                    border.color: cell.selected ? Color.accent : Style.normalBorderColor
                    clip: true

                    Image {
                        id: preview
                        anchors { fill: parent; margins: cell.selected ? 3 : 1; bottomMargin: label.height }
                        source: cell.modelData.preview ? "file://" + cell.modelData.preview : ""
                        sourceSize.width: 320
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    Rectangle {
                        id: label
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: cell.selected ? 3 : 1 }
                        height: name.implicitHeight + Style.space(8)
                        color: cell.selected ? Color.accent : Color.popups.background
                        Text {
                            id: name
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: Style.space(6) }
                            text: cell.modelData.name + (cell.modelData.current ? "  ·  current" : "")
                            elide: Text.ElideRight
                            color: cell.selected ? Color.background : Color.foreground
                            font.family: Style.font.family
                            font.pixelSize: Style.font.bodySmall
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { grid.currentIndex = cell.index; grid.forceActiveFocus(); }
                    onDoubleClicked: view.host.applyTheme(cell.modelData)
                }
            }
        }

        Row {
            anchors.right: parent.right
            spacing: Style.space(8)
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: view.applying
                text: "Applying…"
                color: Color.accent
                font.family: Style.font.family
                font.pixelSize: Style.font.body
            }
            Button { text: "Skip"; visible: !view.applied; onClicked: view.host.skip() }
            Button {
                visible: !view.applied
                text: "Keep current"
                onClicked: view.host.keepTheme()
            }
            Button {
                text: view.applied ? "Continue" : "Apply " + (view.current ? view.current.name : "")
                primary: true
                onClicked: view.applied ? view.host.next() : view.host.applyTheme(view.current)
            }
        }
    }
}
