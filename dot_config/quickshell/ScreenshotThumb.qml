import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs

// The floating thumbnail macOS shows after a capture.
//
// Bottom-right, the captured image at ~180px, gone after five seconds — but the
// five seconds wait for you: while the pointer is on the card the countdown is
// paused and resumes with the time it had left (macOS: "the thumbnail remains
// onscreen until you act on the thumbnail or move the pointer away"). Acting on
// it: click to annotate — satty opens on the file, which is where annotation
// lives now (the old scripts froze the screen and opened satty inline) — swipe
// right to dismiss (the macOS gesture; the file is already saved, so a swipe is
// just a dismiss), right-click for the menu (ThumbMenu.qml), or hit the ✕. A
// recording's card shows the film card instead and opens the file. A clipboard
// capture shows here too, from a temp file that is deleted with the thumbnail
// (see Capture.qml).
//
// The window is exactly the card and its input region is the card, so every
// click outside it still belongs to whatever is underneath — which is also why
// the right-click menu lives in its own window (ThumbMenu.qml).
PanelWindow {
    id: root

    screen: Util.focusedScreen()
    anchors.bottom: true
    anchors.right: true
    implicitWidth: card.width
    implicitHeight: card.height
    margins.right: Theme.margin * 2
    margins.bottom: Theme.margin * 2
    color: "transparent"
    exclusiveZone: -1
    WlrLayershell.namespace: "quickshell-thumb"
    WlrLayershell.layer: WlrLayer.Overlay
    // Never takes the keyboard: this is something you glance at, not
    // something you type into. (The right-click menu does take it, in its own
    // window, so Escape can close it.)
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    mask: Region {
        shape: RegionShape.Rect
        x: 0
        y: 0
        width: card.width
        height: card.height
        radius: Theme.panelRadius
    }

    // ---- auto-hide: five seconds, minus the time spent hovered ---------

    // What is left of the countdown and when its current run started, so
    // hovering pauses it exactly instead of restarting five fresh seconds.
    property real hideRemaining: 5000
    property double hideStamp: 0

    // The right-click menu is acting on the thumbnail, so it counts like a
    // hover: the thumbnail stays up while it is open.
    property bool menuOpen: false

    Timer {
        id: hideTimer
        onTriggered: Capture.dismissThumb()
    }

    function startHide(ms: real): void {
        hideTimer.interval = ms;
        root.hideStamp = Date.now();
        hideTimer.start();
    }

    // The one place that decides whether the countdown runs: not while the
    // pointer is on the card, not while the menu is up, and not mid-drag — a
    // swipe is acting on the thumbnail, and it must not vanish under the
    // finger.
    function syncHide(): void {
        if (cardHover.hovered || root.menuOpen || swipe.pressed) {
            if (hideTimer.running) {
                root.hideRemaining = Math.max(250, hideTimer.interval - (Date.now() - root.hideStamp));
                hideTimer.stop();
            }
        } else if (!hideTimer.running) {
            root.startHide(root.hideRemaining);
        }
    }

    Component.onCompleted: root.startHide(5000)
    onMenuOpenChanged: root.syncHide()

    // ---- the card ------------------------------------------------------

    Rectangle {
        id: card

        width: img.width + Theme.panelPadding * 2
        height: img.height + Theme.panelPadding * 2
        radius: Theme.panelRadius
        color: Theme.panelBg
        border.width: 1
        border.color: Theme.border

        HoverHandler {
            id: cardHover
            onHoveredChanged: root.syncHide()
        }

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

        // ~180px wide, decoded at 4x so it stays sharp on the scaled output. A
        // recording loads no still — it would only fail; the film card below
        // takes its place, and the fallback height keeps the card the same
        // 180x101 footprint a 16:9 shot has.
        Image {
            id: img

            anchors.centerIn: parent
            source: Capture.thumbVideo ? "" : "file://" + Capture.thumbPath
            sourceSize.width: 720
            width: 180
            height: implicitWidth > 0 ? 180 * implicitHeight / implicitWidth : 101
            fillMode: Image.PreserveAspectFit
            visible: !Capture.thumbVideo
        }

        // A recording's card: a film glyph and the file's name instead of the
        // image. macOS would offer trimming here; there is no trimmer in the
        // shell, so clicking opens the recording instead (see act()).
        Rectangle {
            id: film

            anchors.centerIn: parent
            width: 180
            height: 101
            radius: Theme.radius
            color: Theme.alpha("#000000", 0.35)
            border.width: 1
            border.color: Theme.alpha(Theme.border, 0.7)
            visible: Capture.thumbVideo

            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -10
                text: "\uf008"
                color: Theme.purple
                font.family: Theme.fontFamily
                font.pixelSize: 40
            }

            Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 8
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideMiddle
                text: root.fileName()
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }
        }

        // The card itself: click acts on the capture, a rightward drag swipes
        // it away (the file is already saved — a swipe is just a dismiss) and a
        // right-click opens the menu. Declared after the image so the card's
        // clicks come here; the ✕ after it wins its corner.
        MouseArea {
            id: swipe

            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor

            property real startX: 0
            property real startY: 0
            property int held: 0
            property bool dragged: false

            onPressed: (mouse) => {
                swipe.startX = mouse.x;
                swipe.startY = mouse.y;
                swipe.held = mouse.button;
                swipe.dragged = false;
                slideBack.stop();
                root.syncHide();
            }
            onPositionChanged: (mouse) => {
                if (swipe.held !== Qt.LeftButton || !swipe.pressed)
                    return;
                const dx = mouse.x - swipe.startX;
                if (Math.abs(dx) > 6 || Math.abs(mouse.y - swipe.startY) > 6)
                    swipe.dragged = true;
                // Rightward slides the card freely; leftward only nudges, so
                // the gesture can never drag the card away by accident.
                card.x = Math.max(-8, dx);
            }
            onReleased: (mouse) => {
                const dx = mouse.x - swipe.startX;
                if (swipe.dragged) {
                    // A drag of any kind cancels the click; only a rightward
                    // one past a quarter card is the swipe gesture.
                    if (swipe.held === Qt.LeftButton && dx > card.width / 4)
                        slideAway.start();
                    else
                        slideBack.start();
                    root.syncHide();
                    return;
                }
                if (mouse.button === Qt.LeftButton)
                    root.act();
                root.syncHide();
            }
            onClicked: (mouse) => {
                if (mouse.button === Qt.RightButton)
                    root.menuOpen = true;
            }
            onCanceled: root.syncHide()
        }

        // Dismiss. Declared after the swipe area so its click wins the corner.
        Rectangle {
            id: closeBtn

            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 4
            width: 22
            height: 22
            radius: Theme.radiusPill
            color: closeHover.hovered ? Theme.alpha(Theme.red, 0.85) : Theme.alpha(Theme.bg, 0.75)
            border.width: 1
            border.color: Theme.alpha(Theme.red, 0.6)

            Text {
                anchors.centerIn: parent
                text: "✕"
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            HoverHandler {
                id: closeHover
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Capture.dismissThumb()
            }
        }
    }

    // The swipe's slide-out: off the window's right edge — the window is the
    // card, so the card slides toward the screen corner — and then gone.
    NumberAnimation {
        id: slideAway

        target: card
        property: "x"
        to: card.width + Theme.margin * 2
        duration: Theme.animationNormal
        easing.type: Easing.InCubic
        onStopped: Capture.dismissThumb()
    }

    // A drag that is not the swipe snaps the card back.
    NumberAnimation {
        id: slideBack

        target: card
        property: "x"
        to: 0
        duration: Theme.animationFast
        easing.type: Easing.OutCubic
    }

    // ---- the right-click menu -----------------------------------------

    LazyLoader {
        active: root.menuOpen

        ThumbMenu {
            lift: Theme.margin * 2 + card.height + Theme.spacing
            onDismissed: root.menuOpen = false
            onCopyChosen: root.doCopy()
            onMarkupChosen: root.doMarkup()
            onRevealChosen: root.doReveal()
            onSaveChosen: (dir) => root.doSave(dir)
            onDeleteChosen: root.doDelete()
        }
    }

    // ---- acting on the thumbnail --------------------------------------

    // A recording opens with xdg-open; an image goes to satty for markup.
    function act(): void {
        if (Capture.thumbVideo) {
            openProc.command = ["xdg-open", Capture.thumbPath];
            openProc.running = true;
        } else {
            Capture.annotate();
        }
    }

    function fileName(): string {
        return Capture.thumbPath.split("/").pop();
    }

    function doCopy(): void {
        root.menuOpen = false;
        // A capture is always a PNG (grim writes one); a recording goes over
        // with its own mime, the one the file manager shows for it.
        copyProc.command = Capture.thumbVideo ? ["sh", "-c", 'wl-copy --type "$(xdg-mime query filetype "$1")" < "$1"', "sh", Capture.thumbPath] : ["sh", "-c", 'wl-copy --type image/png < "$1"', "sh", Capture.thumbPath];
        copyProc.running = true;
    }

    function doMarkup(): void {
        root.menuOpen = false;
        // Capture.annotate() hides the thumbnail itself and keeps the file for
        // satty, so nothing here may also dismiss it.
        Capture.annotate();
    }

    function doReveal(): void {
        root.menuOpen = false;
        // Open the containing folder, with whatever the system opens folders
        // with — there is no file manager to name here.
        openProc.command = ["xdg-open", Capture.thumbPath.slice(0, Capture.thumbPath.lastIndexOf("/"))];
        openProc.running = true;
    }

    function doSave(dir: string): void {
        root.menuOpen = false;
        // A real save dialog is out of reach, so "Save As…" offers the three
        // macOS folders and moves the file there. The card cannot outlive its
        // file, so the thumbnail goes when the move lands.
        fileProc.command = ["mv", Capture.thumbPath, dir];
        fileProc.running = true;
    }

    function doDelete(): void {
        root.menuOpen = false;
        fileProc.command = ["rm", "-f", Capture.thumbPath];
        fileProc.running = true;
    }

    // The menu's file commands live here rather than in ThumbMenu.qml: this
    // window is what outlives the menu, and every command dismisses the
    // thumbnail once it finishes — so the process is never pulled out from
    // under itself, and a temp capture is only cleaned after its copy or move
    // has really happened.
    Process {
        id: copyProc

        onExited: (exitCode, exitStatus) => Capture.dismissThumb()
    }

    Process {
        id: openProc

        onExited: (exitCode, exitStatus) => Capture.dismissThumb()
    }

    Process {
        id: fileProc

        onExited: (exitCode, exitStatus) => Capture.dismissThumb()
    }
}
