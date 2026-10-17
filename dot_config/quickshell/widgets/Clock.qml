import QtQuick
import qs
import Quickshell

// Clock, and the way into the calendar panel.
//
// SystemClock replaces the waybar `interval` polling: it wakes once a minute
// instead of running a timer that formats a date every second. The format is
// waybar's `{:%a %d %b  %H:%M}` (including the double space) so the bar reads
// the same as before.
BarItem {
    id: root

    panel: "calendar"

    readonly property var clock: SystemClock {
        precision: SystemClock.Minutes
    }

    function format(d: var): string {
        const days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
        const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
        return days[d.getDay()] + " " + Util.pad2(d.getDate()) + " " + months[d.getMonth()] + "  " + Util.pad2(d.getHours()) + ":" + Util.pad2(d.getMinutes());
    }

    Text {
        text: root.format(root.clock.date)
        color: Theme.cyan
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.weight: Font.DemiBold
    }
}
