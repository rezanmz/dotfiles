import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs
import qs as Shell

// The ⇧⌘5 capture toolbar: the macOS Screenshot panel, in this shell's style.
//
// macOS's panel is one dark rounded bar: six tools split into two trios by a
// divider — capture entire screen / window / portion, then record entire
// screen / window / portion — an Options menu, and one primary button that
// reads Capture or Record depending on which trio the selected tool is in.
// The window tools mean "click the window": they keep routing through
// Shell.Capture.beginCapture("window") / Shell.Capture.recordWindow(), which
// open the shell's own picker (Selection.qml). The trios are kept visually
// distinct the way macOS keeps them distinct by iconography: a CAPTURE/RECORD
// label per group, mode glyphs on the chips (red record dot on the record
// trio), red accent on active record chips, and the record group goes live-red
// while a recording runs.
//
// The Options menu is macOS's, in macOS's order and wording: Save to (Desktop /
// Documents / Clipboard / Other Location… — Other reveals the typed-directory
// field in the bar), Timer (Off / 5s / 10s), Microphone (None / Default /
// System audio — greyed while a capture tool is selected, because it only
// applies to recordings), then the checkmarks Show Floating Thumbnail /
// Remember Last Selection / Show Mouse Pointer.
//
// A running recording turns the primary button into Stop Recording. The
// countdown slot and Reselect stay in the bar: a timed capture has to show its
// remaining seconds somewhere, and Reselect draws a fresh crosshair over a
// remembered selection.
//
// There is no bar widget for this panel to hang off (it is opened by keybind or
// IPC, like ⌘⇧5), so unlike the other panels it is not built on Popup.qml — it
// is its own window, bottom-centre like the macOS toolbar. The window is
// created when the panel opens and destroyed when it closes (shell.qml's
// LazyLoader), so the Options menu simply starts closed every time.
//
// `qs as Shell` is not decoration: this file defines the type `Capture`, which
// would shadow the `Capture` singleton of `import qs` inside its own document,
// so the singleton is always addressed as Shell.Capture here.
PanelWindow {
    id: root

    // The Options menu is open.
    property bool optionsOpen: false

    screen: Util.focusedScreen()
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    implicitHeight: card.height + Theme.margin * 2 + (root.optionsOpen ? menu.height + 10 : 0)
    color: "transparent"
    exclusiveZone: -1
    WlrLayershell.namespace: "quickshell-capture"
    WlrLayershell.layer: WlrLayer.Overlay
    // The toolbar takes keyboard focus so Escape reaches it (Enter/backspace too).
    // Nothing dismisses it by itself: Selection owns when the toolbar goes away,
    // because a half-finished selection must not be cancelled by a stray focus
    // change (see Popup.qml).
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    focusable: true

    // Input only on the card (and the Options menu while it is open); the rest
    // of the window is click-through, so an open toolbar never blocks the
    // desktop around it.
    mask: Region {
        shape: RegionShape.Rect
        x: root.optionsOpen ? Math.min(card.x, menu.x) : card.x
        y: root.optionsOpen ? Math.min(card.y, menu.y) : card.y
        width: root.optionsOpen ? Math.max(card.x + card.width, menu.x + menu.width) - x : card.width
        height: root.optionsOpen ? Math.max(card.y + card.height, menu.y + menu.height) - y : card.height
        radius: Theme.panelRadius
    }

    Component.onCompleted: Panels.register(root)
    Component.onDestruction: Panels.unregister(root)

    // One tool segment. The active one is filled — purple for the capture
    // tools, red for the record tools — the same "this is the one" fill the
    // launcher and OSD use. Every chip carries a glyph so the two trios cannot
    // be confused: capture chips show the mode's capture glyph, record chips a
    // red record dot plus the same mode glyph. The codepoints are Hack Nerd
    // Font, rendered and checked one by one the way widgets/Rec.qml validated
    // its stop symbol (U+23FA "⏺" is not in the font and renders as tofu).
    component Chip: Rectangle {
        id: chip

        property alias text: label.text
        property string glyph: ""
        property color glyphColor: Theme.cyan
        property color accent: Theme.purple
        property bool active: false
        signal chosen()

        implicitWidth: inner.implicitWidth + 20
        implicitHeight: 28
        radius: Theme.radius
        color: chip.active ? chip.accent : (chipHover.hovered ? Theme.alpha(Theme.selection, 0.8) : "transparent")
        Behavior on color {
            ColorAnimation {
                duration: Theme.animationFast
            }
        }

        Row {
            id: inner
            anchors.centerIn: parent
            spacing: 5

            Text {
                visible: chip.glyph !== ""
                text: chip.glyph
                color: chip.active ? Theme.bg : chip.glyphColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            Text {
                id: label
                color: chip.active ? Theme.bg : Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }
        }

        HoverHandler {
            id: chipHover
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.chosen()
        }
    }

    // An action button: filled for the primary action, outlined for the rest.
    // `toggled` paints the outlined state as held down (the Options button
    // while its menu is open).
    component Btn: Rectangle {
        id: btn

        property alias text: label.text
        property color accent: Theme.purple
        property bool filled: true
        property bool toggled: false
        signal chosen()

        implicitWidth: label.implicitWidth + 28
        implicitHeight: 30
        radius: Theme.radius
        color: btn.filled ? (btnHover.hovered ? Theme.mix(btn.accent, Theme.fg, 0.15) : btn.accent) : ((btnHover.hovered || btn.toggled) ? Theme.alpha(Theme.selection, 0.8) : "transparent")
        border.width: btn.filled ? 0 : 1
        border.color: Theme.alpha(btn.accent, 0.7)
        Behavior on color {
            ColorAnimation {
                duration: Theme.animationFast
            }
        }

        Text {
            id: label
            anchors.centerIn: parent
            color: btn.filled ? Theme.bg : btn.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            font.bold: true
        }

        HoverHandler {
            id: btnHover
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.chosen()
        }
    }

    // The thin divider between the capture trio and the record trio, the way
    // macOS splits them.
    component Divider: Item {
        implicitWidth: 1
        implicitHeight: 30

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: parent.height - 10
            color: Theme.alpha(Theme.comment, 0.5)
        }
    }

    // A grouped segmented control: chips in a shared rounded container, so
    // they read as one choice like macOS's segmented buttons. `live` paints the
    // record group as running.
    component SegGroup: Rectangle {
        id: group

        property bool live: false

        radius: Theme.radius
        color: group.live ? Theme.alpha(Theme.red, 0.16) : Theme.alpha(Theme.selection, 0.35)
        border.width: 1
        border.color: group.live ? Theme.alpha(Theme.red, 0.8) : Theme.alpha(Theme.border, 0.6)
        implicitWidth: segRow.implicitWidth + 4
        implicitHeight: segRow.implicitHeight + 4

        default property alias items: segRow.data

        RowLayout {
            id: segRow
            anchors.centerIn: parent
            spacing: 0
        }
    }

    // A short label beside each trio — without one the two groups read
    // identically. The record label goes red and reads "recording" while a
    // recording runs, so the label, the group, its active chip and the primary
    // button all say the same thing.
    component GroupLabel: Text {
        property bool live: false

        Layout.alignment: Qt.AlignVCenter
        color: live ? Theme.red : Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        font.capitalization: Font.AllUppercase
        font.bold: live
    }

    // A menu section title, aligned with the menu items' labels (past the
    // checkmark column).
    component MenuHeader: Item {
        id: head

        property alias text: headerLabel.text
        property bool dimmed: false

        width: menuCol.width
        height: 22

        Text {
            id: headerLabel
            anchors.left: parent.left
            anchors.leftMargin: 28
            anchors.verticalCenter: parent.verticalCenter
            color: head.dimmed ? Theme.alpha(Theme.comment, 0.5) : Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            font.capitalization: Font.AllUppercase
        }
    }

    // One menu row: a checkmark column, then the label. `checked` draws the
    // macOS checkmark; `dimmed` greys the row and takes its clicks away, the
    // way macOS dims what does not apply to the selected tool.
    component MenuItem: Rectangle {
        id: item

        property alias text: label.text
        property bool checked: false
        property bool dimmed: false
        signal chosen()

        width: menuCol.width
        height: 26
        radius: Theme.radius
        color: !item.dimmed && itemHover.hovered ? Theme.hoverBg : "transparent"
        Behavior on color {
            ColorAnimation {
                duration: Theme.animationFast
            }
        }

        Text {
            id: tick
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 14
            text: item.checked ? "✓" : ""
            color: Theme.purple
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Text {
            id: label
            anchors.left: tick.right
            anchors.leftMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            color: item.dimmed ? Theme.comment : Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        HoverHandler {
            id: itemHover
        }

        MouseArea {
            anchors.fill: parent
            enabled: !item.dimmed
            cursorShape: Qt.PointingHandCursor
            onClicked: item.chosen()
        }
    }

    // The hairline between the menu's groups.
    component MenuSep: Rectangle {
        width: menuCol.width
        height: 1
        color: Theme.alpha(Theme.comment, 0.35)
    }

    // Escape closes the toolbar. This item is the toolbar's default focus holder:
    // the window takes keyboard focus, but with no item holding it a key press has
    // nowhere to go and Escape did nothing. The custom-directory field takes focus
    // while it is being edited and handles Escape itself, so clearing the field
    // does not also take the toolbar down.
    Item {
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: Panels.close()

        Component.onCompleted: forceActiveFocus()
    }

    Rectangle {
        id: card

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.margin
        width: row.implicitWidth + Theme.panelPadding * 2
        height: row.implicitHeight + Theme.panelPadding * 2
        radius: Theme.panelRadius
        color: Theme.panelBg
        border.width: 1
        border.color: Theme.border

        // Same hairline as every surface in the shell (see Theme.rampStart).
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 1
            height: 2
            radius: parent.radius
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop {
                    position: 0.0
                    color: Theme.alpha(Theme.rampStart, 0.0)
                }
                GradientStop {
                    position: 0.25
                    color: Theme.alpha(Theme.rampStart, 0.9)
                }
                GradientStop {
                    position: 0.6
                    color: Theme.alpha(Theme.rampMid, 0.9)
                }
                GradientStop {
                    position: 1.0
                    color: Theme.alpha(Theme.rampEnd, 0.0)
                }
            }
        }

        RowLayout {
            id: row

            anchors.centerIn: parent
            spacing: Theme.spacing + 4

            // macOS's capture trio: entire screen / window / portion, each with
            // its capture glyph. The window tool means "click the window" — it
            // opens the picker.
            GroupLabel {
                text: "capture"
            }

            SegGroup {
                Chip {
                    text: "Screen"
                    glyph: String.fromCodePoint(0xF108)  // desktop display
                    active: !Shell.Capture.recordingMode && Shell.Capture.mode === "screen"
                    onChosen: {
                        Shell.Capture.mode = "screen";
                        Shell.Capture.recordingMode = false;
                    }
                }
                Chip {
                    text: "Window"
                    glyph: String.fromCodePoint(0xF2D0)  // window
                    active: !Shell.Capture.recordingMode && Shell.Capture.mode === "window"
                    onChosen: {
                        Shell.Capture.mode = "window";
                        Shell.Capture.recordingMode = false;
                    }
                }
                Chip {
                    text: "Portion"
                    glyph: String.fromCodePoint(0xF125)  // crop marks
                    active: !Shell.Capture.recordingMode && Shell.Capture.mode === "selection"
                    onChosen: {
                        Shell.Capture.mode = "selection";
                        Shell.Capture.recordingMode = false;
                    }
                }
            }

            Divider {
            }

            // The record trio: the same modes, each chip led by a red record
            // dot, the whole group red-accented and "live" while a recording
            // runs.
            GroupLabel {
                text: Recorder.recording ? "recording" : "record"
                live: Recorder.recording
            }

            SegGroup {
                live: Recorder.recording

                Chip {
                    text: "Screen"
                    glyph: String.fromCodePoint(0xF111) + " " + String.fromCodePoint(0xF108)  // ⏺ + display
                    glyphColor: Theme.red
                    accent: Theme.red
                    active: Shell.Capture.recordingMode && Shell.Capture.recordTarget === "screen"
                    onChosen: {
                        Shell.Capture.recordTarget = "screen";
                        Shell.Capture.recordingMode = true;
                    }
                }
                Chip {
                    text: "Window"
                    glyph: String.fromCodePoint(0xF111) + " " + String.fromCodePoint(0xF2D0)  // ⏺ + window
                    glyphColor: Theme.red
                    accent: Theme.red
                    active: Shell.Capture.recordingMode && Shell.Capture.recordTarget === "window"
                    onChosen: {
                        Shell.Capture.recordTarget = "window";
                        Shell.Capture.recordingMode = true;
                    }
                }
                Chip {
                    text: "Portion"
                    glyph: String.fromCodePoint(0xF111) + " " + String.fromCodePoint(0xF125)  // ⏺ + crop marks
                    glyphColor: Theme.red
                    accent: Theme.red
                    active: Shell.Capture.recordingMode && Shell.Capture.recordTarget === "selection"
                    onChosen: {
                        Shell.Capture.recordTarget = "selection";
                        Shell.Capture.recordingMode = true;
                    }
                }
            }

            // macOS's "Other Location": the path is typed rather than picked,
            // which avoids a file dialog the shell has no business opening.
            // The Options menu's Save to entry reveals it.
            Row {
                visible: Shell.Capture.saveTo === "other"
                spacing: 8
                height: visible ? 24 : 0

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "folder"
                    color: Theme.comment
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    font.capitalization: Font.AllUppercase
                }

                Rectangle {
                    width: 260
                    height: 22
                    radius: Theme.radius
                    color: Theme.alpha(Theme.selection, 0.6)
                    border.width: 1
                    border.color: Theme.borderStrong

                    TextInput {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        verticalAlignment: TextInput.AlignVCenter
                        text: Shell.Capture.customDir
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        selectByMouse: true
                        onTextChanged: Shell.Capture.customDir = text
                        Keys.onEscapePressed: Shell.Capture.customDir = ""
                    }
                }
            }

            // The timer's remaining seconds, in a fixed slot so the bar does
            // not resize while it counts down.
            Text {
                Layout.preferredWidth: 130
                Layout.alignment: Qt.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                text: Shell.Capture.countdown > 0 ? "capturing in " + Shell.Capture.countdown + "s" : ""
                color: Theme.cyan
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            // macOS's "Remember Last Selection" keeps the previous rectangle;
            // the crosshair cannot pre-draw a frame, so Reselect is how you
            // draw a new one: fresh crosshair, then a portion capture.
            Btn {
                visible: !Shell.Capture.recordingMode && Shell.Capture.rememberSelection && Shell.Capture.lastGeometry !== ""
                text: "Reselect"
                filled: false
                onChosen: {
                    Shell.Capture.reselect = true;
                    Shell.Capture.mode = "selection";
                    Shell.Capture.capture();
                }
            }

            // macOS's Options menu, to the left of the primary button.
            Btn {
                text: "Options ▾"
                filled: false
                toggled: root.optionsOpen
                onChosen: root.optionsOpen = !root.optionsOpen
            }

            // The one primary button: Capture or Record for the selected trio,
            // Stop Recording (red) while that recording runs.
            Btn {
                text: Recorder.recording && Shell.Capture.recordingMode ? "Stop Recording" : (Shell.Capture.recordingMode ? "Record" : "Capture")
                accent: Recorder.recording && Shell.Capture.recordingMode ? Theme.red : Theme.purple
                onChosen: {
                    if (Recorder.recording && Shell.Capture.recordingMode) {
                        Shell.Capture.stopRecording();
                    } else if (Shell.Capture.recordingMode) {
                        if (Shell.Capture.recordTarget === "screen")
                            Shell.Capture.recordScreen();
                        else if (Shell.Capture.recordTarget === "window")
                            Shell.Capture.recordWindow();
                        else
                            Shell.Capture.recordSelection();
                    } else {
                        Shell.Capture.capture();
                    }
                }
            }
        }
    }

    // macOS's Options menu: a dropdown above the bar. Save to, Timer and
    // Microphone are pick-one lists whose choice is checkmarked and which close
    // the menu on pick; the last three are checkmarks that toggle in place so
    // several can be set at once.
    Rectangle {
        id: menu

        visible: root.optionsOpen
        anchors.bottom: card.top
        anchors.bottomMargin: 10
        anchors.right: card.right
        width: 250
        height: menuCol.implicitHeight + 16
        radius: Theme.panelRadius
        color: Theme.panelBg
        border.width: 1
        border.color: Theme.border

        Column {
            id: menuCol
            anchors.fill: parent
            anchors.margins: 8
            spacing: 2

            MenuHeader {
                text: "save to"
            }
            MenuItem {
                text: "Desktop"
                checked: Shell.Capture.saveTo === "desktop"
                onChosen: {
                    Shell.Capture.saveTo = "desktop";
                    root.optionsOpen = false;
                }
            }
            MenuItem {
                text: "Documents"
                checked: Shell.Capture.saveTo === "documents"
                onChosen: {
                    Shell.Capture.saveTo = "documents";
                    root.optionsOpen = false;
                }
            }
            MenuItem {
                text: "Clipboard"
                checked: Shell.Capture.saveTo === "clipboard"
                onChosen: {
                    Shell.Capture.saveTo = "clipboard";
                    root.optionsOpen = false;
                }
            }
            MenuItem {
                text: "Other Location…"
                checked: Shell.Capture.saveTo === "other"
                onChosen: {
                    Shell.Capture.saveTo = "other";
                    root.optionsOpen = false;
                }
            }

            MenuSep {
            }

            MenuHeader {
                text: "timer"
            }
            MenuItem {
                text: "Off"
                checked: Shell.Capture.timer === 0
                onChosen: {
                    Shell.Capture.timer = 0;
                    root.optionsOpen = false;
                }
            }
            MenuItem {
                text: "5s"
                checked: Shell.Capture.timer === 5
                onChosen: {
                    Shell.Capture.timer = 5;
                    root.optionsOpen = false;
                }
            }
            MenuItem {
                text: "10s"
                checked: Shell.Capture.timer === 10
                onChosen: {
                    Shell.Capture.timer = 10;
                    root.optionsOpen = false;
                }
            }

            MenuSep {
            }

            // The microphone only means something for recordings: while a
            // capture tool is selected the section is greyed, macOS-style.
            MenuHeader {
                text: "microphone"
                dimmed: !Shell.Capture.recordingMode
            }
            MenuItem {
                text: "None"
                dimmed: !Shell.Capture.recordingMode
                checked: Shell.Capture.mic === "none"
                onChosen: {
                    Shell.Capture.mic = "none";
                    root.optionsOpen = false;
                }
            }
            MenuItem {
                // Without a detectable default source the option disappears
                // entirely (Capture.micAvailable).
                visible: Shell.Capture.micAvailable
                text: "Default"
                dimmed: !Shell.Capture.recordingMode
                checked: Shell.Capture.mic === "default"
                onChosen: {
                    Shell.Capture.mic = "default";
                    root.optionsOpen = false;
                }
            }
            MenuItem {
                // What you hear, rather than what the microphone hears: the
                // default sink's monitor (Capture.sinkMonitorName).
                visible: Shell.Capture.systemAudioAvailable
                text: "System Audio"
                dimmed: !Shell.Capture.recordingMode
                checked: Shell.Capture.mic === "system"
                onChosen: {
                    Shell.Capture.mic = "system";
                    root.optionsOpen = false;
                }
            }

            MenuSep {
            }

            MenuItem {
                text: "Show Floating Thumbnail"
                checked: Shell.Capture.thumbnail
                onChosen: Shell.Capture.thumbnail = !Shell.Capture.thumbnail
            }
            MenuItem {
                text: "Remember Last Selection"
                checked: Shell.Capture.rememberSelection
                onChosen: Shell.Capture.rememberSelection = !Shell.Capture.rememberSelection
            }
            MenuItem {
                text: "Show Mouse Pointer"
                checked: Shell.Capture.showPointer
                onChosen: Shell.Capture.showPointer = !Shell.Capture.showPointer
            }
        }
    }
}
