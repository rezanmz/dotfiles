import QtQuick
import qs

// System panel: the detail behind the cpu/gpu/ram/temp/disk readouts.
//
// One panel for all five widgets — they are the same question ("what is this
// machine doing") at different granularities, and this is where the numbers that
// used to live in waybar tooltips now live, with a sparkline each so the shape of
// the last two minutes is visible rather than just the current value.
Popup {
    id: root

    name: "system"
    contentWidth: 430

    component StatRow: Item {
        id: row

        required property string label
        property string value: ""
        property color valueColour: Theme.fg
        property string detail: ""
        property var history: null
        property color historyColour: Theme.purple
        property real historyFloor: 0
        property real historyCeiling: 100

        implicitHeight: 36
        width: parent.width

        Text {
            id: labelText

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 52
            text: row.label
            color: Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Text {
            id: valueText

            anchors.left: labelText.right
            anchors.verticalCenter: parent.verticalCenter
            text: row.value
            color: row.valueColour
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Text {
            anchors.left: valueText.right
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: spark.visible ? spark.left : parent.right
            anchors.rightMargin: 10
            text: row.detail
            elide: Text.ElideRight
            color: Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Sparkline {
            id: spark

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 120
            height: 22
            visible: row.history !== null && row.history.length > 1
            values: row.history || []
            lineColour: row.historyColour
            scaleMin: row.historyFloor
            scaleMax: row.historyCeiling
        }
    }

    StatRow {
        label: "cpu"
        value: Math.round(Stats.cpu) + "%"
        valueColour: Theme.green
        detail: Stats.cpuTemp > 0 ? Math.round(Stats.cpuTemp) + "°C package" : ""
        history: Stats.cpuHistory
        historyColour: Theme.green
    }

    StatRow {
        label: "gpu"
        value: Math.round(Stats.gpu) + "%"
        valueColour: Theme.orange
        // Both pools are shown because which one matters depends on the card
        // Stats picked: 16 GiB of VRAM on the discrete RX 9070 XT, where GTT
        // stays near zero, versus the Raphael APU's small carved-out VRAM with
        // everything large spilling into GTT. VRAM in MiB because a
        // GiB-rounded small total reads as "1G".
        detail: Stats.vramTotal > 0 ? "vram " + Math.round(Stats.vramUsed / 1048576) + "M/" + Math.round(Stats.vramTotal / 1048576) + "M  gtt " + Util.gib(Stats.gttUsed) + "/" + Util.gib(Stats.gttTotal, 0) + "G" : ""
        history: Stats.gpuHistory
        historyColour: Theme.orange
    }

    StatRow {
        label: "ram"
        value: Math.round(Stats.memPct) + "%"
        valueColour: Theme.yellow
        detail: Util.gib(Stats.memUsed) + "G / " + Util.gib(Stats.memTotal) + "G"
        history: Stats.memHistory
        historyColour: Theme.yellow
    }

    StatRow {
        label: "temp"
        value: Stats.cpuTemp > 0 ? Math.round(Stats.cpuTemp) + "°C" : "-"
        valueColour: Theme.level(Stats.cpuTemp, 75, 90, Theme.cyan)
        detail: Stats.gpuTemp > 0 ? "gpu " + Math.round(Stats.gpuTemp) + "°C" : ""
        history: Stats.tempHistory
        historyColour: Theme.cyan
        // Temperature has its own band: 20-100 °C shows the shape, where 0-100
        // would flatten it against the floor.
        historyFloor: 20
        historyCeiling: 100
    }

    StatRow {
        label: "disk"
        value: Util.gib(Stats.diskUsed) + "G"
        valueColour: Theme.level(Stats.diskPct, 85, 92, Theme.yellow)
        detail: Math.round(Stats.diskPct) + "% of " + Util.gib(Stats.diskTotal, 0) + "G on /"
    }
}
