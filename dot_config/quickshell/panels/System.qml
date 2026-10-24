import QtQuick
import qs

// System panel: the detail behind the cpu/gpu/ram/temp/disk readouts.
//
// One panel for all five widgets — they are the same question ("what is this
// machine doing") at different granularities, and this is where the numbers that
// used to live in waybar tooltips now live.
//
// Read as four groups rather than five counters: each subsystem gets one
// headline number, one sparkline showing the shape of the last two minutes, and
// one line of secondary figures underneath — the sensors that belong to that
// subsystem (the DIMM temperatures under ram, the junction and VRAM sensors
// under gpu) instead of a separate flat "temp" row that made the reader work out
// which chip a number came from. The disk is the exception: its headline is a
// capacity, not a rate, so it gets a fill bar instead of a sparkline, and its
// throughput goes in the detail line.
Popup {
    id: root

    name: "system"
    contentWidth: 430

    // One number and its context. The headline is the percentage the bar shows,
    // so the panel and the bar can never disagree about "how busy" something is.
    component Metric: Column {
        id: metric

        required property string label
        required property string value
        property color colour: Theme.fg
        // Trend, when the metric has one worth drawing.
        property var history: null
        property color sparkColour: metric.colour
        // Sparkline band. Every headline here is a percentage, so all four
        // trends share the 0-100 scale and can be compared at a glance; a
        // per-metric fit would make an idle gpu look as busy as a loaded cpu.
        property real sparkFloor: 0
        property real sparkCeiling: 100
        // 0-1 fill for capacity metrics, negative to draw no bar.
        property real fraction: -1
        property color fractionColour: Theme.yellow

        width: parent.width
        spacing: 5

        Item {
            width: parent.width
            height: Math.max(labelText.implicitHeight, valueText.implicitHeight)

            Text {
                id: labelText

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: metric.label
                color: Theme.comment
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                font.letterSpacing: 0.3
            }

            Text {
                id: valueText

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: metric.value
                color: metric.colour
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeHeading
            }
        }

        Sparkline {
            width: parent.width
            height: 24
            visible: metric.history !== null && metric.history.length > 1
            values: metric.history || []
            lineColour: metric.sparkColour
            scaleMin: metric.sparkFloor
            scaleMax: metric.sparkCeiling
        }

        // Capacity track: a 4px bar with a 2px radius reads as a gauge without
        // adding a second frame of chrome to the card.
        Rectangle {
            width: parent.width
            height: 4
            radius: 2
            visible: metric.fraction >= 0
            color: Theme.alpha(Theme.selection, 0.85)

            Rectangle {
                height: parent.height
                radius: parent.radius
                width: Math.max(2, parent.width * Math.min(1, Math.max(0, metric.fraction)))
                color: metric.fractionColour

                Behavior on width {
                    NumberAnimation {
                        duration: Theme.animationNormal
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on color {
                    ColorAnimation {
                        duration: Theme.animationFast
                    }
                }
            }
        }
    }

    // label + figure, the unit of the detail line. A chip with an empty value
    // removes itself, which is how a sensor the hardware does not have (a
    // missing CCD sensor, no fan channel, no DIMM hub) stays out of the row
    // instead of printing "0".
    component Chip: Row {
        id: chip

        property string label: ""
        property string value: ""
        property color valueColour: Theme.fg

        spacing: 4
        visible: value !== ""

        Text {
            text: chip.label
            color: Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Text {
            text: chip.value
            color: chip.valueColour
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }
    }

    component Rule: Rectangle {
        width: parent.width
        height: 1
        color: Theme.alpha(Theme.selection, 0.75)
    }

    // Wraps instead of eliding: the gpu detail line is long on this machine and
    // an elided sensor is a sensor the user cannot read.
    component Detail: Flow {
        width: parent.width
        spacing: 12
    }

    // A metric and its sensors, 4px apart, so the 6px column spacing reads as the
    // gap between subsystems rather than the gap between a number and its own
    // explanation.
    component Group: Column {
        width: parent.width
        spacing: 4
    }

    Item {
        width: parent.width
        height: Math.max(titleText.implicitHeight, uptimeText.implicitHeight)

        Text {
            id: titleText

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "system"
            color: Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Text {
            id: uptimeText

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: Util.uptimeText(Stats.uptime)
            color: Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }
    }

    Rule {}

    Group {
        Metric {
            label: "cpu"
            value: Math.round(Stats.cpu) + "%"
            colour: Theme.level(Stats.cpu, 85, 95, Theme.green)
            history: Stats.cpuHistory
            sparkColour: Theme.green
        }

        Detail {
            Chip {
                label: "tctl"
                value: Stats.cpuTemp > 0 ? Math.round(Stats.cpuTemp) + "°C" : ""
                valueColour: Theme.level(Stats.cpuTemp, 75, 90, Theme.fg)
            }
            Chip {
                label: "ccd"
                value: Stats.cpuCcdTemp > 0 ? Math.round(Stats.cpuCcdTemp) + "°C" : ""
            }
            Chip {
                label: "clock"
                value: Stats.cpuFreq > 0 ? (Stats.cpuFreq / 1000).toFixed(1) + "G" : ""
            }
            // Load average is a count of runnable threads, not a percentage: on
            // 16 threads 1.0 is not "1% busy", it is "one thread's worth of
            // work".
            Chip {
                label: "load"
                value: Stats.loadAvg.join(" ")
            }
        }
    }

    Rule {}

    Group {
        Metric {
            label: "gpu"
            value: Math.round(Stats.gpu) + "%"
            colour: Theme.level(Stats.gpu, 85, 95, Theme.orange)
            history: Stats.gpuHistory
            sparkColour: Theme.orange
        }

        Detail {
            Chip {
                label: "vram"
                value: Stats.vramTotal > 0 ? Util.gib(Stats.vramUsed) + "/" + Util.gib(Stats.vramTotal) + "G" : ""
            }
            // GTT is where an APU or a spilled allocation lands, and it stays
            // near zero on the discrete card; drawn only when it is actually in
            // use so the line does not carry a permanent 0.0/15.6G.
            Chip {
                label: "gtt"
                value: Stats.gttUsed > 268435456 ? Util.gib(Stats.gttUsed) + "/" + Util.gib(Stats.gttTotal) + "G" : ""
            }
            Chip {
                label: "edge"
                value: Stats.gpuTemp > 0 ? Math.round(Stats.gpuTemp) + "°C" : ""
                valueColour: Theme.level(Stats.gpuTemp, 80, 95, Theme.fg)
            }
            Chip {
                label: "hotspot"
                value: Stats.gpuJunctionTemp > 0 ? Math.round(Stats.gpuJunctionTemp) + "°C" : ""
                valueColour: Theme.level(Stats.gpuJunctionTemp, 90, 105, Theme.fg)
            }
            Chip {
                label: "mem"
                value: Stats.gpuMemTemp > 0 ? Math.round(Stats.gpuMemTemp) + "°C" : ""
                valueColour: Theme.level(Stats.gpuMemTemp, 85, 95, Theme.fg)
            }
            Chip {
                label: "power"
                value: Stats.gpuPower > 0.5 ? Math.round(Stats.gpuPower) + "W" : ""
            }
            Chip {
                label: "fan"
                value: Stats.gpuFan > 0 ? Math.round(Stats.gpuFan) + "rpm" : ""
            }
        }
    }

    Rule {}

    Group {
        Metric {
            label: "ram"
            value: Math.round(Stats.memPct) + "%"
            colour: Theme.level(Stats.memPct, 85, 95, Theme.yellow)
            history: Stats.memHistory
            sparkColour: Theme.yellow
        }

        Detail {
            Chip {
                label: "used"
                value: Util.gib(Stats.memUsed) + "/" + Util.gib(Stats.memTotal) + "G"
            }
            Chip {
                label: "swap"
                value: Stats.swapTotal > 0 ? Util.gib(Stats.swapUsed) + "/" + Util.gib(Stats.swapTotal) + "G" : ""
            }
            // DDR5 module temperatures from the SPD hubs, in slot order. One
            // number per stick because the two are not the same: the first slot
            // runs a degree or two hotter on this board.
            Chip {
                label: "dimm"
                value: Stats.dimmTemps.length > 0 ? Stats.dimmTemps.map(t => Math.round(t) + "°").join(" / ") : ""
                valueColour: Theme.level(Stats.dimmTemps.reduce((a, b) => Math.max(a, b), 0), 65, 80, Theme.fg)
            }
        }
    }

    Rule {}

    Group {
        Metric {
            label: "disk"
            value: Math.round(Stats.diskPct) + "%"
            colour: Theme.level(Stats.diskPct, 85, 92, Theme.yellow)
            fraction: Stats.diskPct / 100
            fractionColour: Theme.level(Stats.diskPct, 85, 92, Theme.yellow)
        }

        Detail {
            Chip {
                label: "used"
                value: Util.gib(Stats.diskUsed, 0) + "/" + Util.gib(Stats.diskTotal, 0) + "G"
            }
            Chip {
                label: "read"
                value: Util.rate(Stats.diskRead)
            }
            Chip {
                label: "write"
                value: Util.rate(Stats.diskWrite)
            }
        }
    }
}
