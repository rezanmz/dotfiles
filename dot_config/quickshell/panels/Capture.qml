import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs
import qs as Shell

// The ⇧⌘5 capture toolbar: the macOS one, in this shell's style.
//
// macOS has one dark rounded bar with grouped segmented buttons and thin
// dividers: three mode buttons, an Options area, and the action buttons. This
// is that shape in Dracula slate and neon. The options are inline rather than
// behind an Options ▾ menu — there is room in the bar for them and one click
// less per capture.
//
// A Record button flips the bar to its recording controls (Record Entire
// Screen / Record Selected Portion, plus the microphone); the Capture button
// flips it back. While a recording runs the primary button is Stop Recording.
//
// There is no bar widget for this panel to hang off (it is opened by keybind
// or IPC, like ⌘⇧5), so unlike the other panels it is not built on Popup.qml —
// it is its own window, bottom-centre like the macOS toolbar.
//
// `qs as Shell` is not decoration: this file defines the type `Capture`, which
// would shadow the `Capture` singleton of `import qs` inside its own document,
// so the singleton is always addressed as Shell.Capture here.
PanelWindow {
    id: root

    screen: Util.focusedScreen()
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    implicitHeight: card.height + Theme.margin * 2
    color: "transparent"
    exclusiveZone: -1
    WlrLayershell.namespace: "quickshell-capture"
    WlrLayershell.layer: WlrLayer.Overlay
    // Like the popup panels, the toolbar takes keyboard focus so the
    // HyprlandFocusGrab in shell.qml can park it here and close the panel when
    // something outside is clicked (see Popup.qml for why the grab beats
    // PopupWindow.grabFocus).
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    focusable: true

    // Input only on the card; the rest of the window is click-through, so an
    // open toolbar never blocks the desktop around it.
    mask: Region {
        shape: RegionShape.Rect
        x: card.x
        y: card.y
        width: card.width
        height: card.height
        radius: Theme.panelRadius
    }

    Component.onCompleted: Panels.register(root)
    Component.onDestruction: Panels.unregister(root)

    // One segment or option chip. The active one is filled purple — the same
    // "this is the one" fill the launcher and OSD use.
    component Chip: Rectangle {
        id: chip

        property alias text: label.text
        property bool active: false
        signal chosen()

        implicitWidth: label.implicitWidth + 20
        implicitHeight: 28
        radius: Theme.radius
        color: chip.active ? Theme.purple : (chipHover.hovered ? Theme.alpha(Theme.selection, 0.8) : "transparent")
        Behavior on color {
            ColorAnimation {
                duration: Theme.animationFast
            }
        }

        Text {
            id: label
            anchors.centerIn: parent
            color: chip.active ? Theme.bg : Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
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
    component Btn: Rectangle {
        id: btn

        property alias text: label.text
        property color accent: Theme.purple
        property bool filled: true
        signal chosen()

        implicitWidth: label.implicitWidth + 28
        implicitHeight: 30
        radius: Theme.radius
        color: btn.filled ? (btnHover.hovered ? Theme.mix(btn.accent, Theme.fg, 0.15) : btn.accent) : (btnHover.hovered ? Theme.alpha(Theme.selection, 0.8) : "transparent")
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

    // The thin divider between groups.
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
    // they read as one choice like macOS's segmented buttons.
    component SegGroup: Rectangle {
        id: group

        radius: Theme.radius
        color: Theme.alpha(Theme.selection, 0.35)
        border.width: 1
        border.color: Theme.alpha(Theme.border, 0.6)
        implicitWidth: segRow.implicitWidth + 4
        implicitHeight: segRow.implicitHeight + 4

        default property alias items: segRow.data

        RowLayout {
            id: segRow
            anchors.centerIn: parent
            spacing: 0
        }
    }

    component OptLabel: Text {
        color: Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        font.capitalization: Font.AllUppercase
    }

    // An options group: a label, then its chips.
    component OptGroup: RowLayout {
        property alias text: labelText.text

        spacing: Theme.spacing

        OptLabel {
            id: labelText
            Layout.alignment: Qt.AlignVCenter
        }
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

            // The three capture modes, macOS's Entire Screen / Selected
            // Portion / Window.
            SegGroup {
                visible: !Shell.Capture.recordingMode

                Chip {
                    text: "Screen"
                    active: Shell.Capture.mode === "screen"
                    onChosen: Shell.Capture.mode = "screen"
                }
                Chip {
                    text: "Selection"
                    active: Shell.Capture.mode === "selection"
                    onChosen: Shell.Capture.mode = "selection"
                }
                Chip {
                    text: "Window"
                    active: Shell.Capture.mode === "window"
                    onChosen: Shell.Capture.mode = "window"
                }
            }

            // The recording targets — the bar's flipped state.
            SegGroup {
                visible: Shell.Capture.recordingMode

                Chip {
                    text: "Record Entire Screen"
                    active: Shell.Capture.recordTarget === "screen"
                    onChosen: Shell.Capture.recordTarget = "screen"
                }
                Chip {
                    text: "Record Selected Portion"
                    active: Shell.Capture.recordTarget === "selection"
                    onChosen: Shell.Capture.recordTarget = "selection"
                }
            }

            Divider {
                visible: !Shell.Capture.recordingMode
            }

            // The options. macOS puts these behind an Options ▾; the bar has
            // room to show them outright. Save-to/timer/thumbnail are capture
            // options, the microphone is the recording one.
            OptGroup {
                visible: !Shell.Capture.recordingMode
                text: "save to"

                Chip {
                    text: "Desktop"
                    active: Shell.Capture.saveTo === "desktop"
                    onChosen: Shell.Capture.saveTo = "desktop"
                }
                Chip {
                    text: "Pictures"
                    active: Shell.Capture.saveTo === "pictures"
                    onChosen: Shell.Capture.saveTo = "pictures"
                }
                Chip {
                    text: "Clipboard"
                    active: Shell.Capture.saveTo === "clipboard"
                    onChosen: Shell.Capture.saveTo = "clipboard"
                }
                Chip {
                    text: "Other…"
                    active: Shell.Capture.saveTo === "other"
                    onChosen: Shell.Capture.saveTo = "other"
                }
            }

            // macOS's "Other Location": the path is typed rather than picked,
            // which avoids a file dialog the shell has no business opening.
            Row {
                visible: Shell.Capture.saveTo === "other" && !Shell.Capture.recordingMode
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

            OptGroup {
                visible: !Shell.Capture.recordingMode
                text: "timer"

                Chip {
                    text: "Off"
                    active: Shell.Capture.timer === 0
                    onChosen: Shell.Capture.timer = 0
                }
                Chip {
                    text: "5 s"
                    active: Shell.Capture.timer === 5
                    onChosen: Shell.Capture.timer = 5
                }
                Chip {
                    text: "10 s"
                    active: Shell.Capture.timer === 10
                    onChosen: Shell.Capture.timer = 10
                }
            }

            OptGroup {
                visible: !Shell.Capture.recordingMode
                text: "thumbnail"

                Chip {
                    text: "On"
                    active: Shell.Capture.thumbnail
                    onChosen: Shell.Capture.thumbnail = true
                }
                Chip {
                    text: "Off"
                    active: !Shell.Capture.thumbnail
                    onChosen: Shell.Capture.thumbnail = false
                }
            }

            // macOS's "Remember Last Selection": with it on, a selection capture
            // reuses the previous geometry. slurp cannot pre-draw a frame, so
            // Reselect is how you draw a new one.
            OptGroup {
                visible: !Shell.Capture.recordingMode
                text: "selection"

                Chip {
                    text: "Ask every time"
                    active: !Shell.Capture.rememberSelection
                    onChosen: Shell.Capture.rememberSelection = false
                }
                Chip {
                    text: "Remember"
                    active: Shell.Capture.rememberSelection
                    onChosen: Shell.Capture.rememberSelection = true
                }
                Chip {
                    text: "Reselect"
                    visible: Shell.Capture.rememberSelection && Shell.Capture.lastGeometry !== ""
                    active: false
                    onChosen: {
                        Shell.Capture.reselect = true;
                        Shell.Capture.mode = "selection";
                        Shell.Capture.capture();
                    }
                }
            }

            OptGroup {
                visible: Shell.Capture.recordingMode
                text: "microphone"

                Chip {
                    text: "None"
                    active: Shell.Capture.mic === "none"
                    onChosen: Shell.Capture.mic = "none"
                }
                Chip {
                    // Without a detectable default source the option
                    // disappears entirely (Capture.micAvailable).
                    visible: Shell.Capture.micAvailable
                    text: "Default"
                    active: Shell.Capture.mic === "default"
                    onChosen: Shell.Capture.mic = "default"
                }
                Chip {
                    // What you hear, rather than what the microphone hears: the
                    // default sink's monitor (Capture.sinkMonitorName).
                    visible: Shell.Capture.systemAudioAvailable
                    text: "System audio"
                    active: Shell.Capture.mic === "system"
                    onChosen: Shell.Capture.mic = "system"
                }
            }

            Divider {
                visible: Shell.Capture.recordingMode
            }

            // The timer's remaining seconds, in a fixed slot so the bar does
            // not resize while it counts down.
            Text {
                visible: !Shell.Capture.recordingMode
                Layout.preferredWidth: 130
                Layout.alignment: Qt.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                text: Shell.Capture.countdown > 0 ? "capturing in " + Shell.Capture.countdown + "s" : ""
                color: Theme.cyan
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            // Capture mode: capture in the selected mode, or flip over to the
            // recording controls.
            Btn {
                visible: !Shell.Capture.recordingMode
                text: "Capture"
                onChosen: Shell.Capture.capture()
            }
            Btn {
                visible: !Shell.Capture.recordingMode
                text: "Record"
                filled: false
                onChosen: Shell.Capture.recordingMode = true
            }

            // Recording mode: the Capture button flips back (macOS uses it as
            // the way out of the record state), Record starts, and a running
            // recording gets a Stop Recording in red.
            Btn {
                visible: Shell.Capture.recordingMode
                text: "Capture"
                filled: false
                onChosen: Shell.Capture.recordingMode = false
            }
            Btn {
                visible: Shell.Capture.recordingMode && !Recorder.recording
                text: "Record"
                onChosen: Shell.Capture.recordTarget === "screen" ? Shell.Capture.recordScreen() : Shell.Capture.recordSelection()
            }
            Btn {
                visible: Shell.Capture.recordingMode && Recorder.recording
                text: "Stop Recording"
                accent: Theme.red
                onChosen: Shell.Capture.stopRecording()
            }
        }
    }
}
