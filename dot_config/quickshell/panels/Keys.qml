import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs
import qs as Shell

// Keybind cheatsheet: every bind in the Hyprland config, with the comment the
// file carries above it and the command it runs.
//
// The rows are parsed out of dot_config/hypr/modules/60-binds.lua at startup by
// the Keybinds singleton — the config is the only source of truth, so a chord
// that moves shows up moved. A bind without a comment shows its command instead
// of a made-up description.
//
// Built on PanelWindow rather than Popup.qml, and that is deliberate: the
// search field must take real keyboard focus, and a PopupWindow cannot — it is
// a tooltip-role popup, the WlrLayershell attached object refuses to attach to
// it ("Could not create attached properties object"), and grabFocus (the
// xdg-popup grab) leaves the window unmapped against a layer-shell parent.
// Switcher and the capture toolbar take keyboard focus exactly this way
// (PanelWindow + WlrKeyboardFocus.Exclusive). The card, hairline and animation
// are kept from Popup.qml's design; what is given up is the anchoring under a
// bar widget, so the panel drops down centred under the bar instead.
//
// `qs as Shell` is not decoration: this file defines the type `Keys`, which
// would shadow QtQuick's `Keys` attached object inside its own document, so no
// `Keys.on...` handlers may appear here — and the singleton is always addressed
// as Shell.Keybinds (root Keybinds.qml is named that way for the same reason:
// a root Keys.qml shadows `Keys.onPressed` in Switcher.qml and Launcher.qml).
// The name Keys is still safe for this panel: its type reaches sibling panels
// only through the implicit directory import, which ranks below module imports,
// so `Keys.on...` in panels/Network.qml and panels/Capture.qml keeps resolving
// to QtQuick's Keys attached object.
PanelWindow {
    id: root

    screen: Util.focusedScreen()
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    // One strip down from the top: the bar keeps its own clicks, and the window
    // still covers the whole screen below it, so "click somewhere else" works
    // everywhere (see the mouse area below).
    margins.top: Theme.barHeight
    color: "transparent"
    exclusiveZone: -1
    WlrLayershell.namespace: "quickshell-keys"
    WlrLayershell.layer: WlrLayer.Overlay
    // Typing has to reach the search field, so this window owns the keyboard
    // while it is up — the launcher and the switcher do the same.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // Escape closes the panel. A Shortcut rather than Keys.onEscapePressed: this
    // document's own type is named Keys, which shadows the Keys attached object
    // here (same reason the singleton is called Keybinds), so `Keys.on...` cannot
    // be written in this file at all. The panel owns the keyboard while it is up,
    // and nothing in it claims Escape, so the window shortcut fires.
    Shortcut {
        sequence: "Escape"
        onActivated: Panels.close()
    }

    // The bar is an exclusive zone at the top; drop below it.
    readonly property int topGap: Theme.margin

    property string query: ""
    property bool shown: false

    // What the query leaves: chord, description and command all match.
    readonly property var matches: {
        const q = root.query.trim().toLowerCase();
        return Shell.Keybinds.entries.filter(e => q === "" || e.chord.toLowerCase().includes(q) || e.description.toLowerCase().includes(q) || e.command.toLowerCase().includes(q));
    }

    // Flattened for the list: each section gets one header and all of its
    // binds under it (grouped by the first word of the command), in file order
    // within the group.
    readonly property var rows: {
        const out = [];
        const groups = [];
        const bySection = {};
        for (const e of root.matches) {
            if (!Object.prototype.hasOwnProperty.call(bySection, e.section)) {
                bySection[e.section] = [];
                groups.push({ "section": e.section, "entries": bySection[e.section] });
            }
            bySection[e.section].push(e);
        }
        for (const g of groups) {
            out.push({ "header": g.section });
            for (const e of g.entries)
                out.push({ "entry": e });
        }
        return out;
    }

    // The window only exists while the panel is open (the LazyLoader in
    // shell.qml creates and destroys it), so opening is just creation.
    Component.onCompleted: {
        Panels.register(root);
        root.shown = true;
        search.forceActiveFocus();
    }

    Component.onDestruction: Panels.unregister(root)

    component SectionLabel: Text {
        color: Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        font.capitalization: Font.AllUppercase
    }

    // Anywhere that is not the card is "outside": clicking it closes the panel.
    // First child, so the card and every row inside it keep their own clicks.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: Panels.close()
    }

    Rectangle {
        id: card

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: root.topGap
        width: 640
        implicitHeight: content.implicitHeight + Theme.panelPadding * 2
        color: Theme.panelBg
        radius: Theme.panelRadius
        border.width: 1
        border.color: Theme.border

        // Same hairline as Popup.qml's card: a Dracula-spectrum ramp across
        // the top edge, fading out at both ends.
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

        // Popup.qml's entrance, on the card.
        opacity: root.shown ? 1 : 0
        scale: root.shown ? 1 : 0.97
        Behavior on opacity {
            NumberAnimation {
                duration: Theme.animationFast
                easing.type: Easing.OutCubic
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: Theme.animationFast
                easing.type: Easing.OutCubic
            }
        }

        Column {
            id: content

            anchors.fill: parent
            anchors.margins: Theme.panelPadding
            spacing: Theme.spacing

            // The launcher's search row, minus the mode chip: magnifier,
            // field, placeholder, and the count pill.
            RowLayout {
                width: parent.width
                spacing: 10

                Text {
                    text: ""
                    color: Theme.purple
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }

                TextInput {
                    id: search

                    Layout.fillWidth: true
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    focus: true
                    selectByMouse: true
                    clip: true

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "search keybinds"
                        color: Theme.comment
                        font: search.font
                        visible: search.text === ""
                    }

                    onTextChanged: root.query = text
                }

                Rectangle {
                    radius: 8
                    color: Theme.alpha(Theme.purple, 0.15)
                    border.width: 1
                    border.color: Theme.alpha(Theme.purple, 0.35)
                    implicitWidth: countLabel.implicitWidth + 18
                    implicitHeight: countLabel.implicitHeight + 8

                    Text {
                        id: countLabel

                        anchors.centerIn: parent
                        text: root.matches.length + (root.matches.length === 1 ? " bind" : " binds")
                        color: Theme.purple
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }
            }

            Text {
                width: parent.width
                text: "no bind matches"
                visible: root.matches.length === 0
                color: Theme.comment
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            Flickable {
                width: parent.width
                height: Math.min(list.implicitHeight, 560)
                contentHeight: list.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: list

                    width: parent.width
                    spacing: 2

                    Repeater {
                        model: root.rows

                        delegate: Item {
                            id: delegateRoot

                            required property var modelData

                            readonly property bool isHeader: modelData.header !== undefined
                            readonly property var entry: isHeader ? null : modelData.entry

                            width: list.width
                            implicitHeight: isHeader ? 24 : 28

                            SectionLabel {
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                visible: delegateRoot.isHeader
                                text: delegateRoot.isHeader ? modelData.header : ""
                            }

                            RowLayout {
                                anchors.fill: parent
                                spacing: 10
                                visible: !delegateRoot.isHeader

                                // The chord in a pill: purple on the selection
                                // wash, the shell's mono so the modifiers line
                                // up column-wise.
                                Rectangle {
                                    radius: Theme.radiusPill
                                    color: Theme.alpha(Theme.selection, 0.5)
                                    implicitWidth: chordText.implicitWidth + 18
                                    implicitHeight: chordText.implicitHeight + 8

                                    Text {
                                        id: chordText

                                        anchors.centerIn: parent
                                        text: delegateRoot.entry === null ? "" : delegateRoot.entry.chord
                                        color: Theme.purple
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeSmall
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    // A bind the file has no comment for shows
                                    // its command here rather than an
                                    // invented line.
                                    text: delegateRoot.entry === null ? "" : (delegateRoot.entry.description !== "" ? delegateRoot.entry.description : delegateRoot.entry.command)
                                    color: Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    elide: Text.ElideRight
                                }

                                Text {
                                    visible: delegateRoot.entry !== null && delegateRoot.entry.description !== ""
                                    Layout.maximumWidth: 190
                                    text: delegateRoot.entry === null ? "" : delegateRoot.entry.command
                                    color: Theme.comment
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    horizontalAlignment: Text.AlignRight
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
