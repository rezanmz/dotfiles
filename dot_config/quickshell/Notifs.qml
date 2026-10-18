pragma Singleton

// Notification state: the server, the history, the popup set, and
// do-not-disturb.
//
// This replaces dunst. dunst owned org.freedesktop.Notifications and rendered its
// own popups; here the shell owns the name, renders the popups (NotifPopups.qml)
// and keeps the history the old `notif-history` script read back out of
// `dunstctl history`.
//
// keepOnReload is false on purpose: with the default (true) the server re-emits
// everything still alive after a config reload, which double-fills the history on
// every edit.
//
// `popups` is maintained explicitly rather than derived from `entries` with a
// filter binding: a derived binding went stale here in practice (it reported
// three popups while only two entries existed, leaving ghost cards on screen).
// Two small lists that always move together are cheaper to reason about than a
// binding whose dependencies are object fields.
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

Singleton {
    id: root

    // Do-not-disturb: notifications are still accepted and kept in history, they
    // just do not pop up. That is what dunst's pause did, minus the icon.
    property bool dnd: false

    // Cinema mode (a fullscreen window is focused) suppresses popups the same way
    // dnd does, but it is not the user's choice and must not flip the dnd toggle.
    property bool suppress: false

    // Per-application mutes: [{app, until}]. `until` is 0 for "until unmuted".
    property var mutedApps: []

    function isMuted(app: string): bool {
        if (app === "")
            return false;
        const now = Date.now();
        for (const entry of root.mutedApps) {
            if (entry.app === app && (entry.until === 0 || entry.until > now))
                return true;
        }
        return false;
    }

    function muteApp(app: string, minutes: int): void {
        if (app === "")
            return;
        const until = minutes <= 0 ? 0 : Date.now() + minutes * 60000;
        root.mutedApps = root.mutedApps.filter(e => e.app !== app).concat([{
            "app": app,
            "until": until
        }]);
    }

    function unmuteApp(app: string): void {
        root.mutedApps = root.mutedApps.filter(e => e.app !== app);
    }

    // Only the entries that are still in force, so the panel can show them.
    readonly property var activeMutes: root.mutedApps.filter(e => e.until === 0 || e.until > Date.now())

    // Newest first. Each entry is a plain JS object so it can carry the state the
    // Notification itself has no room for (popup or not, and when it arrived).
    property var entries: []

    // Subset of `entries` currently shown as popups.
    property var popups: []

    readonly property int count: root.entries.length

    // Notifications the user has not looked at. Counting *popups* instead would
    // make the bell empty itself as popups time out, which reads as "nothing
    // happened" while the history is full.
    property int unseen: 0

    NotificationServer {
        id: server

        // See the note above: re-emitting on reload would duplicate history.
        keepOnReload: false

        // Capabilities are hints to the sender. Markup stays off: dunst ran with
        // markup = full, but plain text is what senders actually send and turning
        // it on means every body has to be treated as HTML.
        bodySupported: true
        bodyMarkupSupported: false
        bodyHyperlinksSupported: false
        actionsSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: notif => root.add(notif)
    }

    function add(notif): void {
        // tracked keeps the notification alive after this handler returns; the
        // server discards anything untracked.
        notif.tracked = true;

        // Some senders fire a notification with no text at all — udiskie's
        // status-notifier stub, for one, and anything using the "replace my tray
        // icon" idiom. Rendering one produced a blank card that stayed on screen
        // forever when it was marked critical. It is kept in the history, but it
        // does not pop up and it does not ring the bell.
        const blank = notif.summary === "" && notif.body === "";
        // A muted application, or cinema mode, keeps the notification in the
        // history without showing it.
        const silent = root.suppress || root.isMuted(notif.appName);

        const entry = {
            "notification": notif,
            "popup": !root.dnd && !silent && !blank,
            "seen": Panels.current === "notifications" || blank,
            // The Notification has no timestamp of its own, and the centre shows
            // how old each entry is (dunst's history did).
            "time": Date.now()
        };

        // Cap the history the way dunstrc did (history_length = 20), with room
        // for whatever is on screen. Entries dropped by the cap must also leave
        // the popup set: an entry that is in `popups` but no longer in `entries`
        // can never be removed again, which is how a stale card used to stay on
        // screen forever (it renders with no notification behind it, so it comes
        // out as an empty card with a red border that nothing can dismiss).
        const kept = [entry].concat(root.entries.slice(0, 39));
        for (const dropped of root.entries.slice(39)) {
            dropped.removed = true;
            dropped.popup = false;
            if (dropped.notification && dropped.notification.tracked)
                dropped.notification.tracked = false;
        }
        root.entries = kept;
        root.popups = root.popups.filter(e => kept.indexOf(e) !== -1);
        if (entry.popup)
            root.popups = [entry].concat(root.popups);
        if (!entry.seen)
            root.unseen++;

        notif.closed.connect(reason => root.remove(entry));
    }

    // Idempotent *and* re-entrancy safe. Clearing `tracked` makes the server
    // close the notification, which emits `closed`, which calls this again — with
    // no guard that is an infinite loop, and the stack overflow it threw aborted
    // the removal half-way. That is the "blank card nothing can dismiss" bug: the
    // entry stayed in `popups` with no notification behind it.
    function remove(entry): void {
        if (!entry || entry.removed)
            return;
        entry.removed = true;
        entry.popup = false;
        if (entry.notification && entry.notification.tracked)
            entry.notification.tracked = false;
        if (!entry.seen) {
            entry.seen = true;
            root.unseen = Math.max(0, root.unseen - 1);
        }
        root.entries = root.entries.filter(e => e !== entry);
        root.popups = root.popups.filter(e => e !== entry);
    }

    function dismiss(entry): void {
        // dismiss() tells the sender the user closed it; remove() is the local
        // bookkeeping either way.
        entry.notification.dismiss();
        root.remove(entry);
    }

    function clearPopups(): void {
        for (const entry of root.popups.slice())
            entry.notification.expire();
    }

    function clearAll(): void {
        for (const entry of root.entries.slice())
            root.remove(entry);
    }

    function markSeen(): void {
        for (const entry of root.entries)
            entry.seen = true;
        root.unseen = 0;
    }

    function toggleDnd(): void {
        root.dnd = !root.dnd;
    }
}
