import QtQuick
import QtQuick.Layouts
import Quickshell
import qs

// The clock's drop-down: a month view, replacing the waybar calendar tooltip.
//
// All state is plain QML/JS. `shownMonth`/`shownYear` are seeded from the wall
// clock and written by the header buttons, and `buildGrid()` turns them into the
// 42 day objects that always fill the same rectangle. "Today" comes from a
// SystemClock at hour precision: a day rollover always crosses an hour
// boundary, so the highlight cannot go stale and nothing polls the date.
//
// The window is anchored by the Popup base from the widget that opened it (the
// clock hands itself over in BarItem), so this file sets no anchor properties.
Popup {
    id: root

    name: "calendar"
    // 7 columns of ~42px inside the panel padding — wide enough for a
    // comfortable day pill and the "Today" button without crowding the header.
    contentWidth: 320

    readonly property var clock: SystemClock {
        precision: SystemClock.Hours
    }

    // What "today" is measured against, for the highlight and the week footer.
    readonly property var today: clock.date

    // The month on display, seeded from the wall clock. It tracks `today` until
    // the user navigates: an assignment from the header buttons drops the seed
    // binding, which is exactly what we want — from the first click on, where
    // you are is a deliberate choice. The Today button re-seeds.
    property int shownYear: today.getFullYear()
    property int shownMonth: today.getMonth()

    readonly property var monthNames: [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]

    // Monday first, matching the ISO week count in the footer.
    readonly property var weekdayNames: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

    readonly property string monthLabel: monthNames[shownMonth] + " " + shownYear

    // Cells span the panel's content width exactly, so the weekday row and the
    // day grid share one measurement and their columns cannot drift apart.
    readonly property real cellWidth: (contentWidth - Theme.panelPadding * 2) / 7
    readonly property real cellHeight: cellWidth

    readonly property var days: buildGrid(shownYear, shownMonth, today)
    readonly property int weekNumber: isoWeek(today)

    // The 6x7 grid always covers the Monday before the 1st through the Sunday
    // after the 28th, so rows never reflow between months: days that belong to
    // the neighbours are drawn dimmed instead of left blank.
    function buildGrid(year: int, month: int, today: var): var {
        const cells = [];
        const offset = (new Date(year, month, 1).getDay() + 6) % 7;
        for (let i = 0; i < 42; i++) {
            const d = new Date(year, month, 1 - offset + i);
            cells.push({
                day: d.getDate(),
                inMonth: d.getFullYear() === year && d.getMonth() === month,
                isToday: d.getFullYear() === today.getFullYear()
                    && d.getMonth() === today.getMonth()
                    && d.getDate() === today.getDate(),
                isWeekend: d.getDay() === 0 || d.getDay() === 6
            });
        }
        return cells;
    }

    // Colour priority: the today pill outranks the weekend accent, and other
    // months' days stay dimmed so the grid reads as one block.
    function dayColor(cell: var): color {
        if (cell.isToday)
            return Theme.bg;
        if (!cell.inMonth)
            return Theme.comment;
        return cell.isWeekend ? Theme.pink : Theme.fg;
    }

    // ISO 8601 week number: the Thursday of a week decides which year the week
    // belongs to, so early January can still be week 52/53 of the old year.
    function isoWeek(d: var): int {
        const t = new Date(d.getFullYear(), d.getMonth(), d.getDate());
        t.setDate(t.getDate() + 3 - ((t.getDay() + 6) % 7));
        const firstThursday = new Date(t.getFullYear(), 0, 4);
        firstThursday.setDate(firstThursday.getDate() + 3 - ((firstThursday.getDay() + 6) % 7));
        // Math.round absorbs the hour a DST shift can skew the division by.
        return 1 + Math.round((t - firstThursday) / (7 * 86400000));
    }

    function shiftMonth(delta: int): void {
        const d = new Date(shownYear, shownMonth + delta, 1);
        shownYear = d.getFullYear();
        shownMonth = d.getMonth();
    }

    function goToday(): void {
        shownYear = today.getFullYear();
        shownMonth = today.getMonth();
    }

    // Header button, shared by the chevrons and "Today".
    component NavButton: Rectangle {
        id: button

        property alias text: buttonLabel.text
        signal triggered()

        implicitWidth: buttonLabel.implicitWidth + Theme.modulePadding * 2
        implicitHeight: buttonLabel.implicitHeight + Theme.spacing * 2
        radius: Theme.radius
        color: buttonHover.hovered ? Theme.hoverBg : "transparent"

        Text {
            id: buttonLabel
            anchors.centerIn: parent
            color: buttonHover.hovered ? Theme.fg : Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }

        HoverHandler {
            id: buttonHover
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: button.triggered()
        }
    }

    // Header: month + year between the chevrons, "Today" (back to the current
    // month after browsing) at the row's end.
    RowLayout {
        width: parent.width
        spacing: Theme.spacing

        NavButton {
            text: "󰅁" // nf-fa-chevron_left
            onTriggered: root.shiftMonth(-1)
        }

        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.monthLabel
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeHeading
        }

        NavButton {
            text: "󰅂" // nf-fa-chevron_right
            onTriggered: root.shiftMonth(1)
        }

        NavButton {
            text: "Today"
            onTriggered: root.goToday()
        }
    }

    Grid {
        columns: 7

        Repeater {
            model: root.weekdayNames

            delegate: Item {
                required property var modelData

                width: root.cellWidth
                height: weekdayLabel.implicitHeight + Theme.spacing

                Text {
                    id: weekdayLabel
                    anchors.centerIn: parent
                    text: modelData
                    color: Theme.comment
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                }
            }
        }
    }

    Grid {
        columns: 7

        Repeater {
            model: root.days

            delegate: Item {
                id: cell

                required property var modelData

                width: root.cellWidth
                height: root.cellHeight

                // Same pill shape and fill as the focused workspace pill.
                Rectangle {
                    anchors.centerIn: parent
                    width: height
                    height: root.cellHeight - Theme.margin * 2
                    radius: Theme.radius
                    color: cell.modelData.isToday ? Theme.purple : "transparent"
                }

                Text {
                    anchors.centerIn: parent
                    text: cell.modelData.day
                    color: root.dayColor(cell.modelData)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }
            }
        }
    }

    Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: "Week " + root.weekNumber
        color: Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
    }
}
