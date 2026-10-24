import QtQuick
import qs
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets

// Workspace pills, with hover previews.
//
// Only workspaces that exist are shown — an empty workspace that has been
// visited is clutter, which is how the waybar module was configured before
// (`all-outputs: true`, dynamic list). Clicking a pill switches to it through
// HyprlandWorkspace.activate(), which avoids building a dispatch string: this
// machine runs Hyprland's Lua config, where `hyprctl dispatch` parses Lua
// rather than the classic dispatcher syntax.
//
// Hovering a pill for ~1.2s floats a small live preview of that workspace just
// below the pill — the same window the SUPER+Tab switcher would land you on
// (the workspace's most recently focused window). The preview is its own
// PanelWindow on the overlay layer: it is created only while it is shown
// (LazyLoader), streams only while it exists, is never registered with Panels
// (it is a preview, not a panel: it must not close on a workspace change or join
// the panel registry), and takes no keyboard focus. Clicking it switches to the
// workspace the same way the switcher commits.
Item {
    id: root

    // The screen this bar belongs to, set by the Bar that hosts the widget.
    // It is the Quickshell screen (ShellScreen), whose `name` is the output
    // name Hyprland uses.
    property var barScreen: null

    // Which screen this bar is on. The workspaces are split between the panels
    // (see the hypr config), so each bar lists only the workspaces of its own
    // panel: the 4K shows 1-5, the 2K shows 6-10. Without this both bars listed
    // the whole set, which is what made the split read as random.
    //
    // The screen is matched by the connector name, which is what Hyprland
    // calls the output and what the workspace's `monitor` reports.
    readonly property string screenName: barScreen ? barScreen.name : ""

    // This bar's monitor in Hyprland's global layout. The hover preview is a
    // layer window whose margins are measured from its own screen's top-left
    // corner, while the pill position handed over by mapToGlobal is global, so
    // the origin has to be subtracted and the clamp measured against this
    // monitor's width. Hyprland's monitor object is used rather than the
    // ShellScreen because it is the same geometry mapToGlobal reports in.
    readonly property var monitor: {
        const monitors = Hyprland.monitors.values;
        for (let i = 0; i < monitors.length; i++) {
            if (monitors[i].name === root.screenName)
                return monitors[i];
        }
        return null;
    }
    readonly property real monitorX: root.monitor ? root.monitor.x : 0
    readonly property real monitorY: root.monitor ? root.monitor.y : 0
    readonly property real monitorWidth: root.monitor ? root.monitor.width : (root.barScreen ? root.barScreen.width : 1920)

    readonly property var visibleWorkspaces: {
        const out = [];
        const values = Hyprland.workspaces.values;
        const mine = root.screenName;
        for (let i = 0; i < values.length; i++) {
            const ws = values[i];
            // A workspace with no windows that is not the focused one is
            // clutter, which is how the waybar module was configured before
            // (`all-outputs: true`, dynamic list).
            if (ws.toplevels.values.length === 0 && !ws.focused)
                continue;
            // Only this bar's own panel. A workspace that has no monitor yet
            // (it is being created) is skipped rather than shown twice.
            if (mine && ws.monitor && ws.monitor.name !== mine)
                continue;
            out.push(ws);
        }
        out.sort((a, b) => a.id - b.id);
        return out;
    }

    implicitWidth: row.implicitWidth + Theme.margin * 2
    implicitHeight: Theme.barHeight

    // ---- hover preview state ------------------------------------------
    property var previewWs: null
    property bool previewShown: false
    property bool pillHovered: false
    property bool previewHovered: false
    // How many pills currently have the pointer. Counted, not a flag: see
    // pillHover.
    property int hoverCount: 0

    // Screen coordinates of the hovered pill: centre x, and the pill's bottom
    // edge y so the preview hangs just below it.
    property real previewX: 0
    property real previewY: 0

    // Workspace id -> address of the window the shell saw focused on it most
    // recently, the same tracking the switcher does (see Switcher.qml).
    property var recent: ({})

    readonly property int previewWidth: 260
    readonly property int previewCaptureHeight: 146

    Connections {
        target: Hyprland

        function onActiveToplevelChanged(): void {
            const top = Hyprland.activeToplevel;
            if (!top || !top.workspace)
                return;
            const recent = Object.assign({}, root.recent);
            recent[top.workspace.id] = top.address;
            root.recent = recent;
        }
    }

    // Hyprland's IPC reports addresses with an 0x prefix and quickshell does not
    // always keep it, so comparisons normalise it away.
    function sameAddress(a: var, b: var): bool {
        if (!a || !b)
            return false;
        const norm = s => String(s).replace(/^0x/i, "").toLowerCase();
        return norm(a) === norm(b);
    }

    // The window the preview (and the switcher card) shows: the one the shell
    // saw focused on that workspace most recently, else the workspace's own
    // `lastwindow`, else its first toplevel.
    function captureFor(ws: var): var {
        const tops = ws.toplevels.values;
        if (tops.length === 0)
            return null;

        const tracked = root.recent[ws.id];
        for (const t of tops) {
            if (root.sameAddress(t.address, tracked))
                return t;
        }

        const last = ws.lastIpcObject && ws.lastIpcObject.lastwindow ? String(ws.lastIpcObject.lastwindow) : "";
        for (const t of tops) {
            if (root.sameAddress(t.address, last))
                return t;
        }

        return tops[0];
    }

    readonly property var previewCapture: root.previewWs ? root.captureFor(root.previewWs) : null
    readonly property int previewCount: root.previewWs ? root.previewWs.toplevels.values.length : 0

    function pillHover(pill: var): void {
        // Counted, not a flag: when the pointer jumps between pills the leave
        // of the old pill can arrive after the enter of the new one, and a flag
        // would cancel a hover that is still live.
        root.hoverCount++;
        root.pillHovered = true;
        hideTimer.stop();

        // Every pill previews, including the workspace you are on — that is what
        // was asked for, and it is genuinely useful when the window you care about
        // is buried under others.
        const bottom = pill.mapToGlobal(pill.width / 2, pill.height);
        root.previewX = bottom.x;
        root.previewY = bottom.y;
        root.previewWs = pill.modelData;
        hoverTimer.restart();
    }

    function pillLeave(): void {
        root.hoverCount = Math.max(0, root.hoverCount - 1);
        if (root.hoverCount > 0)
            return;
        root.pillHovered = false;
        hoverTimer.stop();
        if (root.previewShown) {
            // Shown already: give the pointer a moment to cross onto the
            // preview itself (it is clickable), then hide if it went elsewhere.
            if (!root.previewHovered)
                hideTimer.restart();
        } else {
            // Left before the delay elapsed: cancelled, never shown.
            root.previewWs = null;
        }
    }

    function previewClick(): void {
        const ws = root.previewWs;
        const capture = root.previewCapture;
        hoverTimer.stop();
        hideTimer.stop();
        root.previewShown = false;
        root.previewHovered = false;
        root.previewWs = null;
        if (!ws)
            return;

        // The switcher's commit path: switch to the workspace, then raise the
        // window the preview showed so the right one is on top.
        Hyprland.dispatch("hl.dsp.focus({workspace = " + ws.id + "})");
        if (capture) {
            const address = String(capture.address).startsWith("0x") ? String(capture.address) : "0x" + String(capture.address);
            Hyprland.dispatch("hl.dsp.focus({window = \"address:" + address + "\"})");
        }
    }

    Timer {
        id: hoverTimer

        // Half a second: long enough not to fire while the pointer crosses the
        // pills on its way somewhere else, short enough to feel like a glance.
        interval: 500
        onTriggered: {
            if (root.pillHovered)
                root.previewShown = true;
        }
    }

    Timer {
        id: hideTimer

        interval: 150
        onTriggered: {
            if (!root.pillHovered && !root.previewHovered) {
                root.previewShown = false;
                root.previewWs = null;
            }
        }
    }

    Row {
        id: row

        anchors.centerIn: parent
        spacing: 6

        Repeater {
            model: root.visibleWorkspaces

            delegate: Rectangle {
                id: pill

                required property var modelData

                readonly property bool focused: modelData.focused
                readonly property bool urgent: modelData.urgent
                // A dot marks workspaces that actually hold windows, so an empty
                // workspace you have visited is distinguishable from a live one
                // without reading the number twice.
                readonly property bool occupied: modelData.toplevels.values.length > 0

                implicitWidth: label.implicitWidth + 20
                height: Theme.barHeight - 10
                anchors.verticalCenter: parent.verticalCenter
                radius: Theme.radius
                color: urgent ? Theme.red : (focused ? Theme.purple : (hover.hovered ? Theme.selection : "transparent"))
                scale: hover.hovered && !focused ? 1.06 : 1.0

                Behavior on color {
                    ColorAnimation {
                        duration: Theme.animationFast
                    }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: Theme.animationFast
                        easing.type: Easing.OutCubic
                    }
                }

                // Urgent is the one state worth animating: something on that
                // workspace is asking for attention.
                SequentialAnimation on opacity {
                    running: pill.urgent
                    loops: Animation.Infinite
                    NumberAnimation {
                        to: 0.5
                        duration: 450
                    }
                    NumberAnimation {
                        to: 1
                        duration: 450
                    }
                }

                Text {
                    id: label

                    anchors.centerIn: parent
                    text: pill.modelData.name
                    color: pill.focused ? Theme.bg : Theme.comment
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 3
                    width: 4
                    height: 4
                    radius: 2
                    visible: pill.occupied && !pill.focused
                    color: Theme.alpha(Theme.fg, 0.45)
                }

                HoverHandler {
                    id: hover

                    onHoveredChanged: {
                        if (hovered)
                            root.pillHover(pill);
                        else
                            root.pillLeave();
                    }
                }

                // A pill can vanish from under the pointer (its workspace
                // closed): balance the hover count so it cannot leak.
                Component.onDestruction: {
                    if (hover.hovered)
                        root.pillLeave();
                }

                MouseArea {
                    id: pillMouse

                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor

                    // Drag a pill downward to pull a floating live view of that
                    // workspace out of the bar (PiP.qml); a plain click still
                    // switches to it.
                    property bool dragging: false
                    property bool suppressClick: false

                    onClicked: {
                        if (pillMouse.suppressClick) {
                            pillMouse.suppressClick = false;
                            return;
                        }
                        pill.modelData.activate();
                    }

                    onPressed: pillMouse.dragging = false

                    onPositionChanged: mouse => {
                        // Screen coordinates, so the window tracks the pointer
                        // one-to-one while it is pulled down.
                        const pointer = pillMouse.mapToGlobal(mouse.x, mouse.y);
                        if (!pillMouse.dragging) {
                            // A few pixels of slop before it counts as a drag.
                            if (mouse.y < 20)
                                return;
                            pillMouse.dragging = true;
                            PiP.beginDrag(pill.modelData.id, pointer.x, pointer.y);
                        } else {
                            PiP.dragTo(pointer.x, pointer.y);
                        }
                    }

                    onReleased: {
                        if (pillMouse.dragging) {
                            PiP.endDrag();
                            pillMouse.dragging = false;
                            // The release happens over the floating window, so no
                            // click follows — but if it does not, do not also
                            // switch workspaces.
                            pillMouse.suppressClick = true;
                        }
                    }

                    onCanceled: {
                        if (pillMouse.dragging) {
                            PiP.endDrag();
                            pillMouse.dragging = false;
                            pillMouse.suppressClick = true;
                        }
                    }
                }
            }
        }
    }

    // The preview. Created while it is shown and destroyed when it hides: an
    // idle window costs the same as a busy one, and a live screencopy is
    // ~25 MiB of buffers — so nothing exists until the pointer has rested.
    LazyLoader {
        active: root.previewShown

        PanelWindow {
            id: preview

            // The bar's own monitor, not the focused one: margins are measured
            // from the window's screen, while previewX/Y come from mapToGlobal in
            // the *global* layout. Taking the focused screen put the card on
            // whichever monitor had focus and measured one monitor's pill
            // position against another monitor's width — on the 1080p screen next
            // to the 4K one, the preview landed at the far right edge.
            screen: root.barScreen
            anchors.top: true
            anchors.left: true
            // Just below the hovered pill, centred on it, clamped on screen. The
            // monitor origin is subtracted because margins are screen-relative.
            margins.top: Math.max(Theme.barHeight, root.previewY - root.monitorY)
            margins.left: Math.max(0, Math.min(root.previewX - root.monitorX - root.previewWidth / 2, root.monitorWidth - root.previewWidth))
            implicitWidth: root.previewWidth
            implicitHeight: root.previewCaptureHeight + 30 + Theme.panelPadding * 2
            color: "transparent"
            exclusiveZone: -1
            // A preview: no keyboard focus, and deliberately NOT registered
            // with Panels, so it never closes on a workspace change.
            focusable: false
            WlrLayershell.namespace: "quickshell-ws-preview"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Rectangle {
                id: card

                anchors.fill: parent
                radius: Theme.panelRadius
                color: Theme.panelBg
                border.width: 1
                border.color: Theme.border

                // Same hairline as every other surface (see Theme.rampStart).
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

                ClippingWrapperRectangle {
                    id: frame

                    anchors.top: parent.top
                    anchors.topMargin: Theme.panelPadding
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: root.previewWidth - Theme.panelPadding * 2
                    height: root.previewCaptureHeight
                    radius: Theme.radius
                    color: Theme.alpha("#000000", 0.5)
                    border.width: 1
                    border.color: Theme.alpha(Theme.border, 0.7)

                    // One child only: a Wrapper component cannot have more
                    // than one, so the capture and its placeholder live inside
                    // this Item.
                    Item {
                        anchors.fill: parent

                        ScreencopyView {
                            anchors.fill: parent
                            captureSource: root.previewCapture ? root.previewCapture.wayland : null
                            live: true
                            constraintSize: Qt.size(root.previewWidth, root.previewCaptureHeight)
                            paintCursor: false
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: root.previewCapture === null
                            text: "empty workspace"
                            color: Theme.comment
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                }

                Row {
                    anchors.top: frame.bottom
                    anchors.topMargin: 6
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: 24
                    spacing: 6

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "workspace " + (root.previewWs ? root.previewWs.name : "?")
                        color: Theme.purple
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        font.bold: true
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.previewCount === 1 ? "1 window" : root.previewCount + " windows"
                        color: Theme.comment
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }

                // The preview is clickable: switching to the workspace it
                // shows is the obvious thing to do with it. Hovering here also
                // keeps the preview alive while the pointer travels from the
                // pill onto it.
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: root.previewHovered = containsMouse
                    onClicked: root.previewClick()
                }
            }
        }
    }
}
