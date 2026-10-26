pragma Singleton

// Removable drives: what is plugged in, what is mounted, and the two policies.
//
// This replaces udiskie's tray icon. That icon was a GTK menu relayed over
// DBusMenu: labels only, no sizes, no mount state, no way to tell a mounted
// stick from an unmounted one, and its two switches were udiskie's internal
// state with no API to reach it from here — clicking them sent a DBusMenu event
// to an item id that no longer existed, so they did nothing at all.
//
// udisks2 still does the privileged part (mount, unmount, power-off; its polkit
// policy allows all three for the active session). The policy part — mount on
// plug, notify on change — is here, because a switch in this panel has to own
// the thing it switches.
//
// The device list is `lsblk -J`: quickshell has no generic D-Bus client, and one
// lsblk run is the whole tree — disk model, partitions, filesystems, mount
// points — in one parse. Hotplug is a `udevadm monitor` line, not a poll.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // ---- preferences -----------------------------------------------------
    //
    // In the state directory, not the config directory: these are switches the
    // user flips, and a `chezmoi apply` must not flip them back.
    //
    // Not Quickshell.statePath(): that resolves inside a per-shell-instance
    // directory the shell never creates, so the write lands nowhere. This
    // directory already exists (it holds the launcher's frecency file).
    readonly property string prefsPath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/quickshell/drives.json"

    property bool automount: true
    property bool notifications: true

    FileView {
        id: prefsFile

        path: root.prefsPath
        blockLoading: true
        watchChanges: false
    }

    function loadPrefs(): void {
        const text = prefsFile.text();
        if (!text)
            return;
        try {
            const parsed = JSON.parse(text);
            if (typeof parsed.automount === "boolean")
                root.automount = parsed.automount;
            if (typeof parsed.notifications === "boolean")
                root.notifications = parsed.notifications;
        } catch (e) {
            // A malformed file is a preference, not a reason not to start.
        }
    }

    function savePrefs(): void {
        prefsFile.setText(JSON.stringify({
            automount: root.automount,
            notifications: root.notifications
        }, null, 2));
    }

    function setAutomount(on: bool): void {
        root.automount = on;
        root.savePrefs();
        // Turning it on is a request to mount what is already plugged in, not
        // only what is plugged in from now on.
        if (on)
            root.refresh();
    }

    function setNotifications(on: bool): void {
        root.notifications = on;
        root.savePrefs();
    }

    Component.onCompleted: root.loadPrefs()

    // ---- the device list -------------------------------------------------
    //
    // One entry per volume, not per disk: a stick with two partitions has two
    // things to mount, and "the drive" is not a thing you can mount.
    property var volumes: []

    // Paths with an operation in flight, and paths automount already tried, so a
    // device that cannot be mounted is not retried on every refresh.
    property var busy: ({})
    property var attempted: ({})

    // Last error from an operation, for the panel to show. Cleared on success.
    property string status: ""

    readonly property bool anyMounted: root.volumes.some(volume => volume.mounted)

    readonly property var disks: {
        const out = [];
        const index = {};
        for (let i = 0; i < root.volumes.length; i++) {
            const volume = root.volumes[i];
            let disk = index[volume.disk];
            if (disk === undefined) {
                disk = {
                    path: volume.disk,
                    model: volume.model,
                    volumes: []
                };
                index[volume.disk] = disk;
                out.push(disk);
            }
            disk.volumes.push(volume);
        }
        return out;
    }

    function refresh(): void {
        if (!listProc.running)
            listProc.running = true;
    }

    function applyList(text: string): void {
        let tree;
        try {
            tree = JSON.parse(text).blockdevices;
        } catch (e) {
            return;
        }
        const out = [];
        for (let i = 0; i < tree.length; i++) {
            const disk = tree[i];
            // Removable USB only. The nvme system disk, the LVM volumes and zram
            // are not drives somebody plugs in, and offering to eject them would
            // be offering to take the machine down.
            if (disk.tran !== "usb" || !(disk.rm || disk.hotplug))
                continue;
            const parts = disk.children || [];
            if (parts.length === 0) {
                out.push(root.volume(disk, disk));
            } else {
                for (let j = 0; j < parts.length; j++)
                    out.push(root.volume(parts[j], disk));
            }
        }
        // Automount attempts are remembered per path and forgotten when the
        // device goes away, so unplugging and replugging a stick tries again.
        const attempted = {};
        for (let i = 0; i < out.length; i++) {
            if (root.attempted[out[i].path])
                attempted[out[i].path] = true;
        }
        root.attempted = attempted;
        root.volumes = out;
        if (!root.automount)
            return;
        for (let i = 0; i < out.length; i++) {
            const volume = out[i];
            if (!volume.mounted && volume.fstype !== "" && !attempted[volume.path])
                root.mount(volume);
        }
    }

    function volume(dev: var, disk: var): var {
        return {
            path: dev.path,
            disk: disk.path,
            model: disk.model || "usb drive",
            label: dev.label || "",
            fstype: dev.fstype || "",
            size: dev.size || "",
            mountpoint: dev.mountpoint || "",
            mounted: (dev.mountpoint || "") !== ""
        };
    }

    // The name to show for a volume: its label, or the device node when the
    // filesystem has none.
    function nameOf(path: string): string {
        for (let i = 0; i < root.volumes.length; i++) {
            const volume = root.volumes[i];
            if (volume.path === path)
                return volume.label !== "" ? volume.label : volume.path;
        }
        return path;
    }

    function isBusy(path: string): bool {
        return root.busy[path] === true;
    }

    function setBusy(path: string, on: bool): void {
        const next = Object.assign({}, root.busy);
        if (on)
            next[path] = true;
        else
            delete next[path];
        root.busy = next;
    }

    // ---- operations ------------------------------------------------------
    //
    // One udisksctl call. The exit code arrives on `exited` and the output on
    // the stdout collector's `onStreamFinished`, in no specified order —
    // measured here: the collector first, so a handler that reads the exit code
    // there sees the previous run's and reports a success as a failure. Both are
    // latched and the job finishes once it has them.
    component Job: Process {
        id: job

        property string target: ""
        property string name: ""
        property int lastExit: -1
        property bool exited: false
        property bool collected: false

        signal finished(int code, string out, string err)

        stdout: StdioCollector {
            id: jobOut

            waitForEnd: true
            onStreamFinished: {
                job.collected = true;
                job.settle();
            }
        }

        stderr: StdioCollector {
            id: jobErr

            waitForEnd: true
        }

        onExited: exitCode => {
            job.lastExit = exitCode;
            job.exited = true;
            job.settle();
        }

        function settle(): void {
            if (!job.exited || !job.collected)
                return;
            job.exited = false;
            job.collected = false;
            job.finished(job.lastExit, jobOut.text, jobErr.text);
        }

        function start(target: string, name: string): void {
            job.target = target;
            job.name = name;
            job.running = true;
        }
    }

    function mount(volume: var): void {
        if (root.isBusy(volume.path) || volume.mounted)
            return;
        const attempted = Object.assign({}, root.attempted);
        attempted[volume.path] = true;
        root.attempted = attempted;
        root.setBusy(volume.path, true);
        mountJob.start(volume.path, volume.label !== "" ? volume.label : volume.path);
    }

    function unmount(volume: var): void {
        if (root.isBusy(volume.path) || !volume.mounted)
            return;
        root.setBusy(volume.path, true);
        unmountJob.start(volume.path, volume.label !== "" ? volume.label : volume.path);
    }

    // Power the whole disk down. udisks2 refuses while any of its filesystems is
    // mounted, which is the safety net that makes this a one-click action.
    function eject(disk: var): void {
        if (root.isBusy(disk.path))
            return;
        root.setBusy(disk.path, true);
        powerJob.start(disk.path, disk.model);
    }

    function open(volume: var): void {
        if (!volume.mounted)
            return;
        browseProc.command = ["setsid", "-f", "kitty", "yazi", volume.mountpoint];
        browseProc.running = true;
    }

    // The last line of an error, which is the one that says why.
    function reason(text: string, fallback: string): string {
        const lines = text.trim().split("\n").filter(line => line !== "");
        return lines.length > 0 ? lines[lines.length - 1] : fallback;
    }

    function notify(text: string): void {
        if (!root.notifications)
            return;
        notifyProc.command = ["notify-send", "-a", "drives", "drives", text];
        notifyProc.running = true;
    }

    // ---- processes -------------------------------------------------------
    Process {
        id: listProc

        // NAME is not decoration: lsblk drops the `children` array from its
        // JSON unless the tree column is asked for, so without it every disk
        // looks like one unpartitioned volume.
        command: ["lsblk", "-J", "-o", "NAME,PATH,TYPE,FSTYPE,LABEL,SIZE,MOUNTPOINT,TRAN,RM,HOTPLUG,MODEL"]

        stdout: StdioCollector {
            id: listOut

            waitForEnd: true
            onStreamFinished: root.applyList(listOut.text)
        }
    }

    // Hotplug. Every block event restarts a short timer instead of refreshing
    // immediately: one plug raises several events (disk, partition table,
    // partition, udev's own change), and each would otherwise be a full lsblk.
    Process {
        id: watcher

        command: ["udevadm", "monitor", "--udev", "--subsystem-match=block"]
        running: true

        stdout: SplitParser {
            onRead: debounce.restart()
        }
    }

    Timer {
        id: debounce

        interval: 250
        onTriggered: root.refresh()
    }

    Job {
        id: mountJob

        command: ["udisksctl", "mount", "-b", target]

        onFinished: (code, out, err) => {
            root.setBusy(mountJob.target, false);
            if (code === 0) {
                root.status = "";
                // "Mounted /dev/sda1 at /run/media/reza/X": the path is the
                // half worth saying out loud.
                root.notify("mounted " + mountJob.name + " at " + out.trim().replace(/^Mounted .*? at /, ""));
            } else {
                root.status = root.reason(err, "mount failed");
            }
            root.refresh();
        }
    }

    Job {
        id: unmountJob

        command: ["udisksctl", "unmount", "-b", target]

        onFinished: (code, out, err) => {
            root.setBusy(unmountJob.target, false);
            if (code === 0) {
                root.status = "";
                root.notify("unmounted " + unmountJob.name);
            } else {
                // The common case is a file manager or a terminal still holding
                // the mount, and udisks2 names it.
                root.status = root.reason(err, "unmount failed");
            }
            root.refresh();
        }
    }

    Job {
        id: powerJob

        command: ["udisksctl", "power-off", "-b", target]

        onFinished: (code, out, err) => {
            root.setBusy(powerJob.target, false);
            if (code === 0) {
                root.status = "";
                root.notify("ejected " + powerJob.name);
            } else {
                root.status = root.reason(err, "eject failed");
            }
            root.refresh();
        }
    }

    Process {
        id: browseProc
    }

    Process {
        id: notifyProc
    }
}
