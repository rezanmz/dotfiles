pragma Singleton

// System metrics for the whole shell: one sampler, many readers.
//
// The waybar setup read these through two helper scripts (gpu-usage, net-speed)
// that waybar executed every 2 seconds, plus its own built-in cpu/memory/
// temperature/disk modules. All of that is one tick here, reading the kernel
// files directly: no process per poll, no JSON to serialise, and the numbers the
// bar shows are the same ones the panels show because there is one source.
//
// Reads are done through FileView with blockLoading, i.e. synchronously on the
// GUI thread. That is deliberate for these files: /proc/stat, /proc/meminfo and
// the sysfs attributes are kernel-generated and a few KB at most, so the read is
// microseconds — cheaper than the fork+exec it replaces.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // 2s matches the old custom/speed and custom/gpu intervals. One tick for
    // every metric keeps the CPU/net deltas aligned on the same window.
    readonly property int interval: 2000

    // ---- discovered paths ----------------------------------------------
    // DRM card numbers are probe-ordered (simpledrm can take card0 and push
    // amdgpu to card1), and hwmon numbering shifts the same way, so both are
    // found by sentinel at startup rather than hardcoded. See the discovery
    // script below.
    property string gpuPath: ""
    property string cpuTempPath: ""
    property string gpuTempPath: ""
    // Full file paths, empty when the sensor does not exist — a FileView bound
    // to "" is skipped by refresh(), so no read is attempted for a channel the
    // hardware lacks.
    property string cpuCcdTempPath: ""
    property string gpuJunctionPath: ""
    property string gpuMemTempPath: ""
    property string gpuPowerPath: ""
    property string gpuFanPath: ""
    property string cpuFreqPath: ""
    property string diskDev: ""
    // One { path, id } per DIMM, in the order the discovery script printed them.
    property var dimmPaths: []
    // The FileViews built from dimmPaths, in the same order.
    property var dimmFiles: []

    // ---- cpu -----------------------------------------------------------
    property real cpu: 0
    property var cpuPrev: null

    // ---- memory --------------------------------------------------------
    property real memUsed: 0
    property real memTotal: 0
    readonly property real memPct: memTotal > 0 ? 100 * memUsed / memTotal : 0

    // ---- gpu -----------------------------------------------------------
    property real gpu: 0
    property real vramUsed: 0
    property real vramTotal: 0
    property real gttUsed: 0
    property real gttTotal: 0
    readonly property real vramPct: vramTotal > 0 ? 100 * vramUsed / vramTotal : 0

    // ---- temperature ---------------------------------------------------
    property real cpuTemp: 0
    property real gpuTemp: 0
    // Second sensor of the same chip: k10temp's Tccd1 (per-CCD) and amdgpu's
    // temp2/temp3 (junction/memory). Zero when the chip exports only one.
    property real cpuCcdTemp: 0
    property real gpuJunctionTemp: 0
    property real gpuMemTemp: 0
    // ~0 on the APU and on cards whose hwmon has no fan/power channel.
    property real gpuPower: 0
    property real gpuFan: 0
    // DDR5 DIMM temperatures, one entry per spd5118 hub, ordered by i2c
    // address (0x51 before 0x53), which is the slot order on this board.
    property var dimmTemps: []

    // ---- cpu clock and load ---------------------------------------------
    // MHz. The kernel's own average across cores, so a boosted core cannot
    // make the readout jump between ticks.
    property real cpuFreq: 0
    property var loadAvg: [0, 0, 0]

    // ---- swap ------------------------------------------------------------
    property real swapUsed: 0
    property real swapTotal: 0

    // ---- disk ----------------------------------------------------------
    property real diskUsed: 0
    property real diskTotal: 0
    readonly property real diskPct: diskTotal > 0 ? 100 * diskUsed / diskTotal : 0
    // Throughput through the block device that carries / (dm-0 here), from
    // /proc/diskstats sectors — the same numbers iostat prints.
    property real diskRead: 0
    property real diskWrite: 0
    property var diskPrev: null

    // ---- uptime ----------------------------------------------------------
    property real uptime: 0

    // ---- network -------------------------------------------------------
    property string iface: ""
    property real netRx: 0
    property real netTx: 0
    property var netPrev: null
    property real lastSample: 0

    // ---- history (sparklines in the system panel) ----------------------
    readonly property int historyLength: 60
    property var cpuHistory: []
    property var memHistory: []
    property var gpuHistory: []

    // ---- discovery -----------------------------------------------------
    // Sentinel-based, mirroring what gpu-usage did and for the same reason: the
    // card that exports gpu_busy_percent is by definition the amdgpu card, so a
    // non-amdgpu device can never be selected.
    //
    // Which card to report is decided by evidence, in this order, because
    // neither the card number nor boot_vga survives a reboot: DRM numbers are
    // probe-ordered (the 9070 XT was card1 on one boot and card0 on the next),
    // and boot_vga pointed at the APU on one boot and at the discrete card on
    // the other. Ranked:
    //   1. drives a connected connector -- what the user actually sees
    //   2. boot_vga = 1
    //   3. larger VRAM
    // Hence the ranking loop rather than a single first-match.
    Process {
        id: discover

        running: true
        command: ["sh", "-c", `
            gpu=""
            best_conn=0
            best_boot=0
            best_vram=0
            for d in /sys/class/drm/card[0-9]*/device; do
                [ -r "$d/gpu_busy_percent" ] || continue
                card="\${d%/device}"
                conn=0
                for st in "$card"-*/status; do
                    [ -r "$st" ] || continue
                    if [ "$(cat "$st")" = "connected" ]; then
                        conn=1
                    fi
                done
                boot=$(cat "$d/boot_vga" 2>/dev/null) || boot=0
                vram=$(cat "$d/mem_info_vram_total" 2>/dev/null) || vram=0
                if [ "$conn" -gt "$best_conn" ] ||
                   { [ "$conn" -eq "$best_conn" ] && [ "$boot" -gt "$best_boot" ]; } ||
                   { [ "$conn" -eq "$best_conn" ] && [ "$boot" -eq "$best_boot" ] && [ "$vram" -gt "$best_vram" ]; }; then
                    gpu="$d"
                    best_conn=$conn
                    best_boot=$boot
                    best_vram=$vram
                fi
            done
            # The temperature must come from the same card as the load: with a
            # discrete GPU next to an APU there are two amdgpu hwmons, and the
            # glob's last match is whichever one the kernel probed last.
            #
            # The extra channels (temp2 = junction, temp3 = VRAM, fan, power) are
            # emitted only when the card exports them, so the FileViews below stay
            # bound to "" on hardware that has no such sensor instead of reading a
            # missing file every tick.
            if [ -n "$gpu" ]; then
                echo "gpu $gpu"
                for h in "$gpu"/hwmon/hwmon*; do
                    echo "gputemp $h"
                    [ -r "$h/temp2_input" ] && echo "gpujunction $h/temp2_input"
                    [ -r "$h/temp3_input" ] && echo "gpumemtemp $h/temp3_input"
                    [ -r "$h/fan1_input" ] && echo "gpufan $h/fan1_input"
                    if [ -r "$h/power1_average" ]; then
                        echo "gpupower $h/power1_average"
                    elif [ -r "$h/power1_input" ]; then
                        echo "gpupower $h/power1_input"
                    fi
                done
            fi
            for h in /sys/class/hwmon/hwmon*; do
                case "$(cat "$h/name" 2>/dev/null)" in
                    k10temp|zenpower)
                        echo "cputemp $h"
                        # Tccd1: the per-CCD sensor, absent on single-CCD parts.
                        [ -r "$h/temp3_input" ] && echo "cpuccd $h/temp3_input"
                        ;;
                    spd5118)
                        # DDR5 DIMM thermal sensor. The third field is the i2c
                        # device name (14-0051, 14-0053, ...), which is what the
                        # panel orders the sticks by: its last two hex digits are
                        # the SPD address, and 0x51 is the slot the firmware scans
                        # first.
                        echo "dimmtemp $h/temp1_input $(basename "$(readlink -f "$h/device" 2>/dev/null)" 2>/dev/null)"
                        ;;
                esac
            done
            # The block device carrying /, for disk throughput. findmnt reports a
            # btrfs subvolume as "/dev/mapper/<vg>-<lv>[/@]", so the trailing
            # bracket group goes first; readlink then resolves the mapper symlink
            # to dm-N, which is the name /proc/diskstats lists.
            dev=$(findmnt -no SOURCE / 2>/dev/null)
            dev=$(echo "$dev" | cut -d'[' -f1)
            dev=$(readlink -f "$dev" 2>/dev/null)
            [ -n "$dev" ] && echo "diskdev \${dev##*/}"
            # cpuinfo_avg_freq is the kernel's average across cores; a single
            # core's scaling_cur_freq follows whichever core is awake and makes
            # the readout flicker between 500 MHz and 5 GHz.
            freq=/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_avg_freq
            [ -r "$freq" ] || freq=/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq
            [ -r "$freq" ] && echo "cpufreq $freq"
        `]
        stdout: StdioCollector {
            id: discoverOut

            waitForEnd: true
            onStreamFinished: root.applyDiscovery(discoverOut.text)
        }
    }

    function applyDiscovery(text: string): void {
        const dimms = [];
        for (const line of text.split("\n")) {
            const [kind, path, extra] = line.trim().split(" ");
            if (!kind || !path)
                continue;
            // First match wins for the card's own channels: a second hwmon under
            // the same card (the APU's, when both are on one card node) must not
            // overwrite the discrete card's sensors.
            switch (kind) {
            case "gpu":
                root.gpuPath = path;
                break;
            case "cputemp":
                root.cpuTempPath = path;
                break;
            case "gputemp":
                if (root.gpuTempPath === "")
                    root.gpuTempPath = path;
                break;
            case "cpuccd":
                root.cpuCcdTempPath = path;
                break;
            case "gpujunction":
                if (root.gpuJunctionPath === "")
                    root.gpuJunctionPath = path;
                break;
            case "gpumemtemp":
                if (root.gpuMemTempPath === "")
                    root.gpuMemTempPath = path;
                break;
            case "gpupower":
                if (root.gpuPowerPath === "")
                    root.gpuPowerPath = path;
                break;
            case "gpufan":
                if (root.gpuFanPath === "")
                    root.gpuFanPath = path;
                break;
            case "diskdev":
                root.diskDev = path;
                break;
            case "cpufreq":
                root.cpuFreqPath = path;
                break;
            case "dimmtemp":
                if (extra)
                    dimms.push({
                        "path": path,
                        "id": extra
                    });
                break;
            }
        }
        // SPD addresses sort the sticks: 14-0051 is the first slot the firmware
        // scans, 14-0053 the second. Hex, because that is what the i2c device
        // name is; parsing it as decimal happens to give the same order for 0x50
        // to 0x57 and stops doing so past 0x59.
        dimms.sort((a, b) => parseInt(a.id.split("-").pop(), 16) - parseInt(b.id.split("-").pop(), 16));
        root.dimmPaths = dimms;
        // Prime the sample so the first tick has something to show.
        root.sample();
    }

    // ---- metric files --------------------------------------------------
    FileView {
        id: statFile
        path: "/proc/stat"
        blockLoading: true
    }

    FileView {
        id: memFile
        path: "/proc/meminfo"
        blockLoading: true
    }

    FileView {
        id: gpuBusyFile
        path: root.gpuPath === "" ? "" : root.gpuPath + "/gpu_busy_percent"
        blockLoading: true
    }

    FileView {
        id: vramUsedFile
        path: root.gpuPath === "" ? "" : root.gpuPath + "/mem_info_vram_used"
        blockLoading: true
    }

    FileView {
        id: vramTotalFile
        path: root.gpuPath === "" ? "" : root.gpuPath + "/mem_info_vram_total"
        blockLoading: true
    }

    FileView {
        id: gttUsedFile
        path: root.gpuPath === "" ? "" : root.gpuPath + "/mem_info_gtt_used"
        blockLoading: true
    }

    FileView {
        id: gttTotalFile
        path: root.gpuPath === "" ? "" : root.gpuPath + "/mem_info_gtt_total"
        blockLoading: true
    }

    FileView {
        id: cpuTempFile
        path: root.cpuTempPath === "" ? "" : root.cpuTempPath + "/temp1_input"
        blockLoading: true
    }

    FileView {
        id: gpuTempFile
        path: root.gpuTempPath === "" ? "" : root.gpuTempPath + "/temp1_input"
        blockLoading: true
    }

    FileView {
        id: cpuCcdTempFile
        path: root.cpuCcdTempPath
        blockLoading: true
    }

    FileView {
        id: gpuJunctionFile
        path: root.gpuJunctionPath
        blockLoading: true
    }

    FileView {
        id: gpuMemTempFile
        path: root.gpuMemTempPath
        blockLoading: true
    }

    // power1_average is in microwatts on amdgpu, like the hwmon convention.
    FileView {
        id: gpuPowerFile
        path: root.gpuPowerPath
        blockLoading: true
    }

    FileView {
        id: gpuFanFile
        path: root.gpuFanPath
        blockLoading: true
    }

    FileView {
        id: cpuFreqFile
        path: root.cpuFreqPath
        blockLoading: true
    }

    FileView {
        id: loadAvgFile
        path: "/proc/loadavg"
        blockLoading: true
    }

    FileView {
        id: diskStatsFile
        path: "/proc/diskstats"
        blockLoading: true
    }

    FileView {
        id: uptimeFile
        path: "/proc/uptime"
        blockLoading: true
    }

    // One FileView per DIMM, created from whatever the discovery script found.
    // The count is not known until it runs, and a FileView is a QObject, so this
    // is an Instantiator over the discovered list rather than a Repeater. Each
    // delegate appends itself to dimmFiles, which is what sample() iterates.
    Instantiator {
        model: root.dimmPaths

        delegate: FileView {
            blockLoading: true
            path: modelData.path

            Component.onCompleted: root.dimmFiles = root.dimmFiles.concat([this])
            Component.onDestruction: root.dimmFiles = root.dimmFiles.filter(f => f !== this)
        }
    }

    FileView {
        id: netRxFile
        path: root.iface === "" ? "" : "/sys/class/net/" + root.iface + "/statistics/rx_bytes"
        blockLoading: true
    }

    FileView {
        id: netTxFile
        path: root.iface === "" ? "" : "/sys/class/net/" + root.iface + "/statistics/tx_bytes"
        blockLoading: true
    }

    // ---- disk ----------------------------------------------------------
    // df is the only metric that needs a process: the kernel exposes no
    // statfs through a readable file. Once every 30s is plenty for a root
    // filesystem that moves by megabytes, and it is what waybar used.
    Process {
        id: diskProc

        command: ["df", "-B1", "/"]
        stdout: StdioCollector {
            id: diskOut

            waitForEnd: true
            onStreamFinished: root.sampleDisk(diskOut.text)
        }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: diskProc.running = true
    }

    // ---- sampling ------------------------------------------------------
    Timer {
        interval: root.interval
        running: true
        repeat: true
        onTriggered: root.sample()
    }

    // The active interface comes from NetworkManager rather than parsing
    // `ip route`, so it follows a wifi/ethernet switch without a subprocess. The
    // lookup itself lives in NetworkState, which the bar readout and the network
    // panel use too, so "the active interface" means one thing in the shell.
    readonly property var activeDevice: NetworkState.activeDevice

    onActiveDeviceChanged: root.iface = root.activeDevice ? root.activeDevice.name : ""

    function sample(): void {
        const now = Date.now();
        const elapsed = root.lastSample > 0 ? (now - root.lastSample) / 1000 : 0;
        root.lastSample = now;

        refresh();

        sampleCpu(statFile.text());
        sampleMem(memFile.text());

        if (root.gpuPath !== "") {
            root.gpu = Number(gpuBusyFile.text()) || 0;
            root.vramUsed = Number(vramUsedFile.text()) || 0;
            root.vramTotal = Number(vramTotalFile.text()) || 0;
            root.gttUsed = Number(gttUsedFile.text()) || 0;
            root.gttTotal = Number(gttTotalFile.text()) || 0;
        }
        if (root.cpuTempPath !== "")
            root.cpuTemp = (Number(cpuTempFile.text()) || 0) / 1000;
        if (root.gpuTempPath !== "")
            root.gpuTemp = (Number(gpuTempFile.text()) || 0) / 1000;
        if (root.cpuCcdTempPath !== "")
            root.cpuCcdTemp = (Number(cpuCcdTempFile.text()) || 0) / 1000;
        if (root.gpuJunctionPath !== "")
            root.gpuJunctionTemp = (Number(gpuJunctionFile.text()) || 0) / 1000;
        if (root.gpuMemTempPath !== "")
            root.gpuMemTemp = (Number(gpuMemTempFile.text()) || 0) / 1000;
        if (root.gpuPowerPath !== "")
            root.gpuPower = (Number(gpuPowerFile.text()) || 0) / 1e6;
        if (root.gpuFanPath !== "")
            root.gpuFan = Number(gpuFanFile.text()) || 0;
        if (root.cpuFreqPath !== "")
            root.cpuFreq = (Number(cpuFreqFile.text()) || 0) / 1000;

        sampleLoad(loadAvgFile.text());
        sampleUptime(uptimeFile.text());

        // The delegates create themselves when dimmPaths lands, so the array is
        // rebuilt from the objects rather than indexed by path: same order, and
        // it cannot go stale if a FileView is destroyed.
        if (root.dimmFiles.length > 0) {
            const temps = [];
            for (const file of root.dimmFiles)
                temps.push((Number(file.text()) || 0) / 1000);
            root.dimmTemps = temps;
        }

        if (elapsed > 0)
            root.sampleDiskIo(diskStatsFile.text(), elapsed);

        if (root.iface !== "" && elapsed > 0) {
            const rx = Number(netRxFile.text()) || 0;
            const tx = Number(netTxFile.text()) || 0;
            if (root.netPrev) {
                // Counters reset when an interface flaps; clamp instead of
                // reporting a negative rate.
                root.netRx = Math.max(0, (rx - root.netPrev[0]) / elapsed);
                root.netTx = Math.max(0, (tx - root.netPrev[1]) / elapsed);
            }
            root.netPrev = [rx, tx];
        } else if (root.iface === "") {
            root.netRx = 0;
            root.netTx = 0;
            root.netPrev = null;
        }

        root.cpuHistory = pushHistory(root.cpuHistory, root.cpu);
        root.memHistory = pushHistory(root.memHistory, root.memPct);
        root.gpuHistory = pushHistory(root.gpuHistory, root.gpu);
    }

    // Sparkline history. A fresh array each tick is what makes the change
    // notification fire; 60 numbers is not worth being clever about.
    function pushHistory(history: var, value: real): var {
        const out = history.slice(Math.max(0, history.length - (root.historyLength - 1)));
        out.push(value);
        return out;
    }

    // FileView caches what it read: a second call to text() returns the same
    // bytes until the file is reloaded. That is why an un-refreshed /proc/stat
    // always produced a zero CPU delta — the two samples were the same read.
    // reload() starts the read and waitForJob() blocks until it lands; a few KB
    // from the kernel is cheaper than the fork+exec this replaces.
    function refresh(): void {
        const files = [statFile, memFile, gpuBusyFile, vramUsedFile, vramTotalFile, gttUsedFile, gttTotalFile, cpuTempFile, gpuTempFile, cpuCcdTempFile, gpuJunctionFile, gpuMemTempFile, gpuPowerFile, gpuFanFile, cpuFreqFile, loadAvgFile, diskStatsFile, uptimeFile, netRxFile, netTxFile].concat(root.dimmFiles);
        for (const file of files) {
            if (file.path === "")
                continue;
            file.reload();
            file.waitForJob();
        }
    }

    function sampleCpu(text: string): void {
        // "cpu  user nice system idle iowait irq softirq steal guest guest_nice"
        const fields = text.slice(0, text.indexOf("\n")).split(/\s+/).slice(1).map(Number);
        const idle = fields[3] + fields[4];
        const total = fields.reduce((a, b) => a + b, 0);
        if (root.cpuPrev) {
            const dIdle = idle - root.cpuPrev[0];
            const dTotal = total - root.cpuPrev[1];
            if (dTotal > 0)
                root.cpu = Math.max(0, Math.min(100, 100 * (1 - dIdle / dTotal)));
        }
        root.cpuPrev = [idle, total];
    }

    function sampleMem(text: string): void {
        let total = 0;
        let available = 0;
        let swapTotal = 0;
        let swapFree = 0;
        for (const line of text.split("\n")) {
            const match = line.match(/^(MemTotal|MemAvailable|SwapTotal|SwapFree):\s+(\d+)\s+kB/);
            if (!match)
                continue;
            const bytes = Number(match[2]) * 1024;
            switch (match[1]) {
            case "MemTotal":
                total = bytes;
                break;
            case "MemAvailable":
                available = bytes;
                break;
            case "SwapTotal":
                swapTotal = bytes;
                break;
            case "SwapFree":
                swapFree = bytes;
                break;
            }
        }
        root.memTotal = total;
        root.memUsed = Math.max(0, total - available);
        root.swapTotal = swapTotal;
        root.swapUsed = Math.max(0, swapTotal - swapFree);
    }

    // "0.78 2.23 1.58 1/1545 8228" — the three load averages, then the runnable
    // count and the last pid.
    function sampleLoad(text: string): void {
        const fields = text.trim().split(/\s+/);
        if (fields.length < 3)
            return;
        root.loadAvg = [Number(fields[0]) || 0, Number(fields[1]) || 0, Number(fields[2]) || 0];
    }

    // "8228.13 45678.90" — seconds since boot, then idle seconds.
    function sampleUptime(text: string): void {
        root.uptime = Number(text.trim().split(/\s+/)[0]) || 0;
    }

    // /proc/diskstats for the block device carrying /:
    // "major minor name reads merges sectors_read ms_read writes merges
    //  sectors_written ms_write ..." — sectors are always 512 bytes, whatever
    // the device's logical block size is.
    function sampleDiskIo(text: string, elapsed: real): void {
        if (root.diskDev === "")
            return;
        for (const line of text.split("\n")) {
            const fields = line.trim().split(/\s+/);
            if (fields[2] !== root.diskDev)
                continue;
            const read = (Number(fields[5]) || 0) * 512;
            const write = (Number(fields[9]) || 0) * 512;
            if (root.diskPrev) {
                // Same counter-reset clamp as the network rates.
                root.diskRead = Math.max(0, (read - root.diskPrev[0]) / elapsed);
                root.diskWrite = Math.max(0, (write - root.diskPrev[1]) / elapsed);
            }
            root.diskPrev = [read, write];
            return;
        }
    }

    function sampleDisk(text: string): void {
        // "Filesystem 1B-blocks Used Available Use% Mounted"
        const line = text.split("\n")[1];
        if (!line)
            return;
        const fields = line.split(/\s+/);
        root.diskTotal = Number(fields[1]) || 0;
        root.diskUsed = Number(fields[2]) || 0;
    }
}
