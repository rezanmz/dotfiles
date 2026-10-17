import QtQuick
import qs
import Quickshell

// Clock, and the way into the calendar panel.
//
// SystemClock replaces the waybar `interval` polling: it wakes once a minute
// instead of running a timer that formats a date every second. The format is
// waybar's `{:%a %d %b  %H:%M}` (including the double space) so the bar reads
// the same as before.
//
// The hairline under the time is the day, filling from left to right — the one
// flourish on the bar that is not decoration: it answers "how much of today is
// left" at a glance, which is what a clock is for.
BarItem {
    id: root

    panel: "calendar"

    readonly property var clock: SystemClock {
        precision: SystemClock.Minutes
    }

    readonly property real dayProgress: {
        const d = root.clock.date;
        return (d.getHours() * 3600 + d.getMinutes() * 60 + d.getSeconds()) / 86400;
    }

    function format(d: var): string {
        const days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
        const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
        return days[d.getDay()] + " " + Util.pad2(d.getDate()) + " " + months[d.getMonth()] + "  " + Util.pad2(d.getHours()) + ":" + Util.pad2(d.getMinutes());
    }

    Column {
        spacing: 3

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.format(root.clock.date)
            color: Theme.cyan
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.weight: Font.DemiBold
        }

        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 54
            height: 2

            Rectangle {
                anchors.fill: parent
                radius: 1
                color: Theme.alpha(Theme.comment, 0.4)
            }

            Rectangle {
                height: parent.height
                radius: 1
                width: parent.width * root.dayProgress
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop {
                        position: 0.0
                        color: Theme.alpha(Theme.rampStart, 0.9)
                    }
                    GradientStop {
                        position: 1.0
                        color: Theme.alpha(Theme.rampEnd, 0.9)
                    }
                }
                Behavior on width {
                    NumberAnimation {
                        duration: Theme.animationNormal
                    }
                }
            }
        }
    }
}
