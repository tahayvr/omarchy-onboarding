import QtQuick

// One font glyph as an icon: its inked shape (not the font's box) is scaled
// to fit `size` and centered in it, so glyphs from different fonts (Nerd Font,
// Omarchy's own) line up and match in size.
Item {
    id: icon

    property string glyph: ""
    property string family: ""
    property color color: "white"
    property real size: 32

    width: size
    height: size

    // The glyph measured at a reference size; everything scales from it.
    readonly property real ref: 100
    TextMetrics {
        id: metrics
        font.family: icon.family
        font.pixelSize: icon.ref
        text: icon.glyph
    }
    readonly property rect ink: metrics.tightBoundingRect
    readonly property real ratio: ink.width > 0 && ink.height > 0 ? icon.size / Math.max(ink.width, ink.height) : 0

    Text {
        id: text
        visible: icon.ratio > 0
        text: icon.glyph
        color: icon.color
        font.family: icon.family
        font.pixelSize: icon.ref * icon.ratio
        // Put the ink's center at the item's center. The ink box is relative
        // to the pen position on the baseline.
        x: icon.size / 2 - (icon.ink.x + icon.ink.width / 2) * icon.ratio
        y: icon.size / 2 - (text.baselineOffset + (icon.ink.y + icon.ink.height / 2) * icon.ratio)
    }
}
