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
            // No reserved space, and no input region: an OSD must never move
            // windows or eat clicks.
            exclusiveZone: 0
            mask: Region {}
            WlrLayershell.namespace: "quickshell-osd"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            // Soft glow behind the pill: two low-alpha rounded rectangles, which
            // is as close to a bloom as QML gets without a shader.
            Rectangle {
                anchors.centerIn: card
                width: card.width + 12
                height: card.height + 12
                radius: Theme.radiusPill
                color: Theme.alpha(Sound.muted ? Theme.comment : Theme.purple, 0.10)
            }

            Rectangle {
                id: card

                anchors.fill: parent
                radius: Theme.radiusPill
                color: Theme.panelBg
                border.width: 1
                border.color: Theme.alpha(Sound.muted ? Theme.comment : Theme.purple, 0.55)
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
                        anchors.verticalCenter: parent.verticalCenter
                        width: 170
                        height: 6
                        radius: 3
                        color: Theme.alpha(Theme.comment, 0.35)

                        Rectangle {
                            height: parent.height
                            radius: parent.radius
                            width: parent.width * (root.kind === "mic" ? 1 : Math.max(0, Math.min(1, Sound.volume)))
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop {
                                    position: 0.0
                                    color: root.kind === "mic" ? Theme.green : Theme.rampStart
                                }
                                GradientStop {
                                    position: 1.0
                                    color: root.kind === "mic" ? Theme.green : (Sound.muted ? Theme.comment : Theme.rampMid)
                                }
                            }
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
