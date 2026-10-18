import QtQuick
import Quickshell
import Quickshell.Wayland
import qs

// Volume OSD.
//
// The old setup had no OSD at all: the volume keys called wpctl and the only
// feedback was the percentage in the bar. This shows a card at the bottom of the
// screen whenever the sink volume, its mute state, or the microphone mute state
// changes — including when the change came from somewhere else (pavucontrol, a
// browser).
//
// The window is created only while it is visible (LazyLoader) and takes no input
// at all (empty click mask), so it can never swallow a click.
Scope {
    id: root

    property bool showing: false
    property string kind: "volume"

    // Volume changes also arrive while the shell is starting up, as pipewire
    // enumerates devices; without this the OSD flashes on login.
    property bool armed: false

    Timer {
        interval: 2500
        running: true
        onTriggered: root.armed = true
    }

    Timer {
        id: hideTimer
        interval: 1500
        onTriggered: root.showing = false
    }

    function show(kind: string): void {
        if (!root.armed)
            return;
        root.kind = kind;
        root.showing = true;
        hideTimer.restart();
    }

    Connections {
        target: Sound

        function onVolumeChanged(): void {
            root.show("volume");
            // Only once the startup enumeration is over; see the armed timer.
            if (root.armed)
                Feedback.volumeTick();
        }
        function onMutedChanged(): void {
            root.show("volume");
        }
        function onMicMutedChanged(): void {
            root.show("mic");
        }
    }

    LazyLoader {
        active: root.showing

        PanelWindow {
            id: window

            screen: Util.focusedScreen()
            anchors.bottom: true
            margins.bottom: 140
            implicitWidth: 300
            implicitHeight: 54
            color: "transparent"
            // No reserved space, and the input region is the card alone: the OSD
            // must never move windows or eat clicks meant for what is behind it,
            // but the card itself is a slider you can drag (macOS's volume HUD is
            // grabbable, and a HUD that looks like a slider and ignores you is
            // what this used to be).
            exclusiveZone: 0
            mask: Region {
                shape: RegionShape.Rect
                x: 0
                y: 0
                width: card.width
                height: card.height
                radius: Theme.radiusPill
            }
            WlrLayershell.namespace: "quickshell-osd"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Rectangle {
                id: card

                anchors.fill: parent
                radius: Theme.panelRadius
                color: Theme.panelBg
                border.width: 1
                border.color: Theme.border

                // The shell's signature hairline, the same one the bar's bottom
                // edge and every panel card carry. The halo that used to be here
                // belonged to no other surface, which is why this read as foreign.
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
                opacity: 0
                y: 24

                Component.onCompleted: {
                    opacity = 1;
                    y = 0;
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.animationNormal
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on y {
                    NumberAnimation {
                        duration: Theme.animationNormal
                        easing.type: Easing.OutCubic
                    }
                }

                // Dragging anywhere on the card sets the volume across the track's
                // span, and hovering or dragging holds the OSD up instead of
                // letting it fade out under your hand.
                MouseArea {
                    id: drag

                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true

                    function setFromX(x: real): void {
                        const left = track.mapToItem(card, 0, 0).x;
                        const f = Math.max(0, Math.min(1, (x - left) / track.width));
                        Sound.setVolume(f);
                    }

                    onPressed: mouse => {
                        hideTimer.stop();
                        setFromX(mouse.x);
                    }
                    onPositionChanged: mouse => {
                        if (pressed)
                            setFromX(mouse.x);
                    }
                    onReleased: hideTimer.restart()
                    onWheel: wheel => {
                        const d = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : (wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y : wheel.angleDelta.x);
                        if (d !== 0)
                            Sound.adjustVolume(d > 0 ? Sound.step : -Sound.step);
                        hideTimer.restart();
                    }
                    onEntered: hideTimer.stop()
                    onExited: {
                        if (!pressed)
                            hideTimer.restart();
                    }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 12

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            if (root.kind === "mic")
                                return Sound.micMuted ? "\uf131" : "\uf130";
                            if (Sound.muted)
                                return "\uf026";
                            return Sound.volume < 0.34 ? "\uf026" : (Sound.volume < 0.67 ? "\uf027" : "\uf028");
                        }
                        color: {
                            if (root.kind === "mic")
                                return Sound.micMuted ? Theme.red : Theme.green;
                            return Sound.muted ? Theme.comment : Theme.purple;
                        }
                        font.family: Theme.fontFamily
                        font.pixelSize: 22
                    }

                    Rectangle {
                        id: track

                        anchors.verticalCenter: parent.verticalCenter
                        width: 170
                        height: 6
                        radius: 3
                        color: Theme.alpha(Theme.comment, 0.35)

                        Rectangle {
                            height: parent.height
                            radius: parent.radius
                            width: parent.width * (root.kind === "mic" ? 1 : Math.max(0, Math.min(1, Sound.volume)))
                            // Flat accent, not a gradient: the volume readout in the
                            // bar and the mixer's rows are both plain purple, and the
                            // HUD should not be the one surface that differs.
                            color: root.kind === "mic" ? Theme.green : (Sound.muted ? Theme.comment : Theme.purple)
                            Behavior on width {
                                NumberAnimation {
                                    duration: Theme.animationFast
                                }
                            }
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 44
                        text: {
                            if (root.kind === "mic")
                                return Sound.micMuted ? "muted" : "live";
                            return Sound.muted ? "muted" : Math.round(Sound.volume * 100) + "%";
                        }
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                    }
                }
            }
        }
    }
}
