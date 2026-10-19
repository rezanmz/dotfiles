import QtQuick
import qs
import Quickshell

// One clickable bar module: padding, hover highlight, click, scroll.
//
// Everything in the bar goes through this so spacing, hover behaviour and the
// panel toggling rule are defined once. A widget with a `panel` name opens that
// panel on left click; one without is a read-only readout.
Item {
    id: root

    default property alias content: contentArea.data

    // Panel key in Panels, or "" for a readout that does not open anything.
    property string panel: ""
    // Which mouse button opens the panel. Widgets that keep a left-click action
    // (media transport, tray items) move the panel to another button.
    property int panelButton: Qt.LeftButton
    property bool interactive: true

    // Right-click and scroll are passed through for widgets that need them
    // (media controls, volume, workspace cycling).
    signal clicked(int button)
    signal scrolled(int delta)

    // A hairline to the left of the module, to mark where one group of
    // readouts ends and the next begins. The bar is a single run of modules
    // and without a break the eye has to work out which numbers belong
    // together; the divider is a mark, not a border -- it is short, faint and
    // inset from the top and bottom so it does not close the bar off.
    property bool separator: false

    implicitWidth: contentArea.implicitWidth + Theme.modulePadding * 2 + (root.separator ? Theme.separatorWidth : 0)
    implicitHeight: Theme.barHeight

    // The window this item lives in — popups anchored to it need it.
    readonly property var barWindow: Panels.barWindow

    // Panel state for this widget. Several widgets can open the same panel (the
    // network readout and the throughput readout both open `network`), so only
    // the one that was actually clicked is marked as active — matching on the
    // panel name alone lit up both of them.
    readonly property bool panelOpen: root.panel !== "" && Panels.current === root.panel
    readonly property bool panelAnchor: Panels.anchorItem === root

    // Panels find their anchor through this registry, so a panel can also be
    // opened from a keybind or the IPC instead of a click.
    Component.onCompleted: Panels.registerAnchor(root.panel, root)

    HoverHandler {
        id: hover
        enabled: root.interactive
    }

    // The hairline, drawn to the left of the module's own padding so it sits
    // in the gap between two groups rather than crowding the content.
    Rectangle {
        visible: root.separator
        anchors.left: parent.left
        anchors.leftMargin: Theme.separatorWidth / 2
        anchors.verticalCenter: parent.verticalCenter
        width: 1
        height: parent.height - Theme.separatorHeight * 2
        color: Theme.alpha(Theme.comment, 0.35)
    }

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 5
        anchors.bottomMargin: 5
        radius: Theme.radius
        color: (hover.hovered || (root.panelOpen && root.panelAnchor)) ? Theme.hoverBg : "transparent"
        Behavior on color {
            ColorAnimation {
                duration: Theme.animationFast
            }
        }
    }

    Item {
        id: contentArea

        // Centered on the item. Size comes from the children, and the parent's
        // implicit size comes from this item's implicit size — keeping the size
        // binding off `anchors` is what stops that from being a loop (which QML
        // resolves to NaN).
        anchors.centerIn: parent
        width: implicitWidth
        height: implicitHeight
        implicitWidth: childrenRect.width
        implicitHeight: childrenRect.height
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.interactive
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor

        onClicked: mouse => {
            root.clicked(mouse.button);
            if (root.panel !== "" && mouse.button === root.panelButton)
                Panels.toggle(root.panel, root);
        }
        // Any axis and either encoding counts. A high-resolution or smooth wheel
        // reports pixelDelta and leaves angleDelta at zero, and a tilted wheel
        // reports x rather than y; widgets only need the direction, so the first
        // non-zero value wins.
        onWheel: wheel => {
            // A *count* of steps, not a raw delta: one step per detent, however the
            // events were packed (see Wheel.qml).
            const n = Wheel.steps(wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x, wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y : wheel.pixelDelta.x, "bar");
            if (n !== 0)
                root.scrolled(n);
        }
    }
}
