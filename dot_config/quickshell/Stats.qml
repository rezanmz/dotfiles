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
import Quickshell.Networking
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

    // ---- disk ----------------------------------------------------------
    property real diskUsed: 0
    property real diskTotal: 0
    readonly property real diskPct: diskTotal > 0 ? 100 * diskUsed / diskTotal : 0

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
    // non-amdgpu device can never be selected. boot_vga wins when there is more
    // than one, since that is the one driving the console.
    Process {
        id: discover

        running: true
        command: ["sh", "-c", `
            for d in /sys/class/drm/card*/device; do
                [ -r "$d/gpu_busy_percent" ] || continue
                if [ -r "$d/boot_vga" ] && [ "$(cat "$d/boot_vga")" = "1" ]; then
                    echo "gpu $d"
                else
                    echo "gpu-later $d"
                fi
            done
            for h in /sys/class/hwmon/hwmon*; do
                case "$(cat "$h/name" 2>/dev/null)" in
                    k10temp|zenpower) echo "cputemp $h" ;;
                    amdgpu) echo "gputemp $h" ;;
                esac
            done
        `]
        stdout: StdioCollector {
            id: discoverOut

            waitForEnd: true
            onStreamFinished: root.applyDiscovery(discoverOut.text)
        }
    }

    function applyDiscovery(text: string): void {
        for (const line of text.split("\n")) {
            const [kind, path] = line.trim().split(" ");
            if (!kind || !path)
                continue;
            if (kind === "gpu" || (kind === "gpu-later" && root.gpuPath === ""))
                root.gpuPath = path;
            else if (kind === "cputemp")
                root.cpuTempPath = path;
            else if (kind === "gputemp")
                root.gpuTempPath = path;
        }
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
    // `ip route`, so it follows a wifi/ethernet switch without a subprocess.
    readonly property var activeDevice: {
        const devices = Networking.devices.values;
        for (let i = 0; i < devices.length; i++) {
            if (devices[i].connected)
                return devices[i];
        }
        return null;
    }

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
        const files = [statFile, memFile, gpuBusyFile, vramUsedFile, vramTotalFile, gttUsedFile, gttTotalFile, cpuTempFile, gpuTempFile, netRxFile, netTxFile];
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
        for (const line of text.split("\n")) {
            const match = line.match(/^(MemTotal|MemAvailable):\s+(\d+)\s+kB/);
            if (!match)
                continue;
            const bytes = Number(match[2]) * 1024;
            if (match[1] === "MemTotal")
                total = bytes;
            else
                available = bytes;
        }
        root.memTotal = total;
        root.memUsed = Math.max(0, total - available);
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
