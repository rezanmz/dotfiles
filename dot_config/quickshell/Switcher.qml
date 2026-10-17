import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs

// SUPER+Tab window switcher, with live thumbnails.
//
// This replaces snappy-switcher (an external daemon with its own IPC server, its
// own config and its own layer surface). Doing it here means the switcher shares
// the shell's theme, and — the reason it exists — the thumbnails are *live*:
// each card is a ScreencopyView capturing the window as it is right now, not a
// snapshot taken when the overlay opened.
//
// Behaviour, matching what a switcher should feel like:
//   hold SUPER, tap Tab        cycle forward (Shift+Tab back)
//   release SUPER              switch to the highlighted window
//   click a card               switch to it
//   Esc                        cancel
//
// Ordering is most-recently-used, which is what makes tapping Tab twice land on
// the window you were on two windows ago. Hyprland does not expose focus history,
// so it is tracked here from Hyprland.activeToplevel.
Scope {
    id: root

    property bool showing: false
    property int selected: 0

    // MRU list of window addresses, most recent first. Kept in the shell rather
    // than derived from Hyprland.toplevels, whose order is creation order.
    property var order: []

    // Live thumbnails are only worth paying for while the overlay is up.
    readonly property bool live: root.showing

    Connections {
        target: Hyprland

        function onActiveToplevelChanged(): void {
            const toplevel = Hyprland.activeToplevel;
            if (!toplevel)
                return;
            const address = toplevel.address;
            root.order = [address].concat(root.order.filter(a => a !== address)).slice(0, 40);
        }
    }

    // Windows to offer, MRU first, with anything that no longer exists dropped.
    readonly property var candidates: {
        const alive = Hyprland.toplevels.values;
        const out = [];
        const seen = {};

        for (const address of root.order) {
            for (let i = 0; i < alive.length; i++) {
                if (alive[i].address === address && !seen[address]) {
                    seen[address] = true;
                    out.push(alive[i]);
                }
            }
        }
        // Anything the shell has not seen focused yet (started before the shell,
        // or focused while a reload happened) goes last, in Hyprland's order.
        for (let i = 0; i < alive.length; i++) {
            if (!seen[alive[i].address]) {
                seen[alive[i].address] = true;
                out.push(alive[i]);
            }
        }
        return out;
    }

    readonly property var current: root.candidates.length > 0 ? root.candidates[Math.min(root.selected, root.candidates.length - 1)] : null

    function open(): void {
        if (root.showing) {
            root.next();
            return;
        }
        // Candidates are MRU-first, so index 0 is the window you are already on:
        // opening with it selected would make a single tap-and-release a no-op.
        // Preselecting the previous window is what alt-tab does.
        root.selected = root.candidates.length > 1 ? 1 : 0;
        root.showing = true;
    }

    function close(): void {
        root.showing = false;
    }

    function next(): void {
        if (root.candidates.length === 0)
            return;
        root.selected = (root.selected + 1) % root.candidates.length;
    }

    function previous(): void {
        if (root.candidates.length === 0)
            return;
        root.selected = (root.selected - 1 + root.candidates.length) % root.candidates.length;
    }

    function commit(): void {
        const target = root.current;
        root.close();
        if (!target)
            return;

        // hl.dsp.focus with an `address:` selector focuses the window and, when
        // it lives on another workspace, switches to that workspace — one call.
        //
        // It is also the only thing that works: Toplevel.activate() (xdg
        // activation) is ignored by Hyprland for a window the shell does not own
        // (verified — focus did not move, and the cross-workspace case only looked
        // right because the workspace switch itself focused the last window), and
        // the bare address without the `address:` prefix is rejected with
        // "window not found".
        // Hyprland's IPC reports addresses with a 0x prefix and the Lua selector
        // requires it ("window not found" without), while quickshell does not
        // always keep the prefix — so it is added when missing.
        const address = target.address.startsWith("0x") ? target.address : "0x" + target.address;
        Hyprland.dispatch("hl.dsp.focus({window = \"address:" + address + "\"})");
    }

    IpcHandler {
        target: "switcher"

        function toggle(): void {
            root.open();
        }
        function next(): void {
            root.open();
        }
        function previous(): void {
            if (!root.showing)
                root.open();
            else
                root.previous();
        }
        function close(): void {
            root.close();
        }
    }

    LazyLoader {
        active: root.showing

        PanelWindow {
            id: window

            screen: Util.focusedScreen()
            anchors.top: true
            anchors.left: true
            anchors.right: true
            anchors.bottom: true
            color: "transparent"
            exclusiveZone: -1
            WlrLayershell.namespace: "quickshell-switcher"
            WlrLayershell.layer: WlrLayer.Overlay
            // Exclusive: the overlay has to see the SUPER release to know when to
            // commit, which is the whole point of the gesture.
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            focusable: true

            Rectangle {
                anchors.fill: parent
                color: Theme.alpha("#000000", 0.55)

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.close()
                }
            }

            // Keyboard: Tab cycles, releasing SUPER commits, Esc cancels.
            Item {
                anchors.fill: parent
                focus: true

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Tab || event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
                        root.next();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
                        root.previous();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                        root.commit();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Escape) {
                        root.close();
                        event.accepted = true;
                    }
                }

                // The gesture ends when the modifier is let go. Qt delivers the
                // release to whichever surface holds keyboard focus, which is
                // this overlay for as long as it is up.
                Keys.onReleased: event => {
                    if (event.key === Qt.Key_Super_L || event.key === Qt.Key_Super_R || event.key === Qt.Key_Meta)
                        root.commit();
                }
            }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: 22

                // Where you would land, spelled out. This is the one piece of
                // text in the overlay, so it says the useful thing.
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 10

                    Text {
                        text: "\uf0d9"
                        color: Theme.purple
                        font.family: Theme.fontFamily
                        font.pixelSize: 20
                    }

                    Text {
                        id: header

                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            if (!root.current)
                                return "nothing to switch to";
                            const ws = root.current.workspace;
                            const name = ws ? ws.name : "?";
                            const focused = ws && ws.focused;
                            return focused ? "workspace " + name : "jumping to workspace " + name;
                        }
                        color: root.current && root.current.workspace && !root.current.workspace.focused ? Theme.pink : Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                    }
                }

                // Filmstrip. The whole row slides so the selected card stays
                // centred, which reads as "moving through" the windows.
                Item {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: window.width
                    height: 300
                    clip: true

                    Row {
                        id: strip

                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 18

                        // Centred by hand: the strip is as wide as its contents,
                        // and the selected card is pulled to the middle.
                        x: window.width / 2 - (root.selected * (cardWidth + strip.spacing)) - cardWidth / 2
                        Behavior on x {
                            NumberAnimation {
                                duration: Theme.animationNormal
                                easing.type: Easing.OutCubic
                            }
                        }

                        readonly property int cardWidth: 340

                        Repeater {
                            model: root.candidates

                            delegate: Item {
                                id: slot

                                required property var modelData
                                required property int index

                                readonly property bool current: index === root.selected
                                readonly property bool live: root.live && Math.abs(index - root.selected) <= 1

                                width: strip.cardWidth
                                height: 250
                                opacity: slot.current ? 1 : 0.62
                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: Theme.animationFast
                                    }
                                }

                                scale: slot.current ? 1.04 : 1.0
                                Behavior on scale {
                                    NumberAnimation {
                                        duration: Theme.animationNormal
                                        easing.type: Easing.OutBack
                                    }
                                }

                                ClippingWrapperRectangle {
                                    id: frame

                                    anchors.top: parent.top
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: parent.width
                                    height: 212
                                    radius: Theme.panelRadius
                                    color: Theme.alpha(Theme.bg, 0.85)
                                    border.width: slot.current ? 2 : 1
                                    border.color: slot.current ? Theme.purple : Theme.border

                                    // One child only: a Wrapper component cannot
                                    // have more than one, so the capture and its
                                    // placeholder live inside this Item.
                                    Item {
                                        anchors.fill: parent

                                        ScreencopyView {
                                            anchors.fill: parent
                                            anchors.margins: 2
                                            captureSource: slot.live && slot.modelData.wayland ? slot.modelData.wayland : null
                                            // Only the highlighted card streams: a live
                                            // screencopy per card is ~25 MiB of buffers each
                                            // (measured: +80 MiB with three cards streaming).
                                            // The neighbours still show real content, captured
                                            // once, which is enough to recognise them.
                                            live: slot.current
                                            // Ask the compositor to scale down before it sends
                                            // the frame; the card is 340px wide either way.
                                            constraintSize: Qt.size(340, 212)
                                            paintCursor: false
                                        }

                                        // Shown until the first frame arrives, and
                                        // when a window is too new to capture.
                                        Text {
                                            anchors.centerIn: parent
                                            visible: !slot.live
                                            text: "\uf2d0"
                                            color: Theme.comment
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 30
                                        }
                                    }
                                }

                                Text {
                                    anchors.top: frame.bottom
                                    anchors.topMargin: 8
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: parent.width - 8
                                    horizontalAlignment: Text.AlignHCenter
                                    text: Util.elide(slot.modelData.title || slot.modelData.wayland.appId || "", 34)
                                    color: slot.current ? Theme.fg : Theme.comment
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.bold: slot.current
                                }

                                Text {
                                    anchors.top: frame.bottom
                                    anchors.topMargin: 26
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    visible: slot.modelData.workspace && !slot.modelData.workspace.focused
                                    text: "workspace " + (slot.modelData.workspace ? slot.modelData.workspace.name : "?")
                                    color: Theme.pink
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.selected = slot.index;
                                        root.commit();
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "release SUPER to switch   ·   tab cycles   ·   esc cancels"
                    color: Theme.comment
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                }
            }
        }
    }
}
