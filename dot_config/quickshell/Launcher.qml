import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import "Fuzzy.js" as Fuzzy

// Launcher: applications and the clipboard history.
//
// Replaces anyrun, whose two jobs were "run an app" (applications plugin) and
// "pick a line from stdin" (the stdin plugin that clipboard-pick and dunst's
// dmenu fed). Both live here now, and the clipboard mode also removes the
// `cliphist list | anyrun | cliphist decode | wl-copy` pipeline: the shell decodes
// the entry and writes it to the clipboard itself.
//
// Ranking is Fuzzy.js (the same shape anyrun's rink plugin had), searched over
// name + genericName + keywords + comment + exec basename with the name
// weighted highest, and ordered by frecency — applications come from
// DesktopEntries, so nothing is re-read from disk per keystroke.
//
// The apps mode also carries the power menu and a calculator. The session
// actions (lock, log out, power off, reboot, suspend) are ordinary searchable
// rows — every one carries a "Power menu —" description so a single query
// surfaces the whole group, like anyrun's actions plugin did — and they rank
// below real applications for an ambiguous query. A destructive row needs Enter
// twice: the first press arms it (the row says so), the second runs it, and any
// other key or typing disarms it. A query that parses as arithmetic gets a
// "= result" row above everything else, and Enter copies the result.
// Applications with Terminal=true run in kitty: DesktopEntry.execute() ignores
// runInTerminal.
Scope {
    id: root

    property bool showing: false
    property string mode: "apps"
    property string query: ""
    // Changing the selection (arrow keys, hover) drops a pending confirmation.
    property int selected: 0
    onSelectedChanged: root.confirmArmed = false
    property var clipboardLines: []
    property string pendingLine: ""

    // A destructive power row is armed by one Enter and run by the next; any
    // other key or typing drops the arming (see the search field's handlers).
    property bool confirmArmed: false

    // Launch history: {id: {count, last}} with `last` in ms since the epoch,
    // persisted as JSON by frecencyLoad/frecencySave below. Reassigned (never
    // mutated in place) so the results binding re-evaluates.
    property var frecency: ({})

    // Card surface: the design language's near-black (darker than Theme.bg),
    // not a Theme token.
    readonly property color cardBg: "#1e1f29"

    // Cap on how many matches are materialised. The list scrolls, so this is a
    // sanity bound rather than the old "8 rows and no scrolling" limit anyrun had
    // upstream (which made rows past the cap unreachable).
    readonly property int maxResults: 300
    readonly property int rowHeight: 38
    readonly property int visibleRows: 10

    function open(mode: string): void {
        root.mode = mode;
        root.query = "";
        root.selected = 0;
        root.confirmArmed = false;
        root.showing = true;
        if (mode === "clipboard")
            clipList.running = true;
    }

    function close(): void {
        root.showing = false;
        root.confirmArmed = false;
    }

    function toggle(mode: string): void {
        if (root.showing && root.mode === mode)
            root.close();
        else
            root.open(mode);
    }

    // ---- applications --------------------------------------------------
    readonly property var applications: {
        const out = [];
        const apps = DesktopEntries.applications.values;
        for (let i = 0; i < apps.length; i++) {
            // NoDisplay entries are the ones that exist for mime-type handling,
            // not for launching by hand.
            if (!apps[i].noDisplay)
                out.push(apps[i]);
        }
        return out;
    }

    // The session actions anyrun's actions plugin carried, same commands (the
    // session is uwsm-managed, so log out is `uwsm stop`). Every description
    // opens with "Power menu —" so one query — "power" — matches the whole
    // group; without it subsequence matching would find only "Power off". They
    // have no icon, so each carries a glyph instead. The four destructive rows
    // are marked for the two-Enter confirmation in activate().
    readonly property var powerActions: [
        {
            "name": "Lock",
            "command": "loginctl lock-session",
            "description": "Power menu — lock the session screen",
            "glyph": "",
            "confirm": false
        },
        {
            "name": "Log out",
            "command": "uwsm stop",
            "description": "Power menu — end the session and return to ly",
            "glyph": "",
            "confirm": true
        },
        {
            "name": "Power off",
            "command": "systemctl poweroff || poweroff",
            "description": "Power menu — shut the system down",
            "glyph": "",
            "confirm": true
        },
        {
            "name": "Reboot",
            "command": "systemctl reboot || reboot",
            "description": "Power menu — restart the system",
            "glyph": "",
            "confirm": true
        },
        {
            "name": "Suspend",
            "command": "systemctl suspend-then-hibernate",
            "description": "Power menu — suspend, then hibernate if still asleep after 45 min",
            "glyph": "",
            "confirm": true
        },
        {
            "name": "Hibernate",
            "command": "systemctl hibernate",
            "description": "Power menu — write memory to disk and power off",
            "glyph": "",
            "confirm": true
        }
    ]

    // Basename of the executable, e.g. "google-chrome-stable" for
    // Exec=/usr/bin/google-chrome-stable %U. Searches "chrome" by command.
    function execBasename(app: var): string {
        const cmd = app.command;
        const first = cmd.length > 0 ? cmd[0] : app.execString.trim().split(/\s+/)[0];
        const parts = first.split("/");
        return parts[parts.length - 1];
    }

    // The weighted fields an application is searched over. The name carries the
    // biggest weight so name matches outrank the rest; each keyword is its own
    // field so a token cannot match across keyword boundaries.
    function appFields(app: var): var {
        const fields = [
            { "text": app.name, "weight": 3 },
            { "text": app.genericName, "weight": 1.5 },
            { "text": root.execBasename(app), "weight": 1.2 },
            { "text": app.comment, "weight": 0.8 }
        ];
        const kws = app.keywords;
        for (let i = 0; i < kws.length; i++)
            fields.push({ "text": kws[i], "weight": 1 });
        return fields;
    }

    // The session actions are searched over name + description, description at
    // half weight (anyrun's actions plugin did the same) so "Power off" leads
    // for "power" while the shared prefix still surfaces the whole group.
    function powerFields(action: var): var {
        return [
            { "text": action.name, "weight": 3 },
            { "text": action.description, "weight": 1.5 }
        ];
    }

    // Recency first, count as the tie-break. Reza's ask was "populate it with the
    // most recent items": a count-weighted score (the previous behaviour) could
    // keep something launched fifty times last month above the thing launched
    // five minutes ago, which is not what an empty search box should show.
    function frecencyValue(id: string): real {
        const rec = root.frecency[id];
        if (rec === undefined)
            return 0;
        const ageDays = Math.max(0, Date.now() - rec.last) / 86400000;
        return rec.count / (1 + ageDays);
    }

    function byFrecency(entries: var): var {
        const out = entries.slice();
        out.sort((a, b) => {
            const ra = root.frecency[a.id];
            const rb = root.frecency[b.id];
            const la = ra === undefined ? -1 : ra.last;
            const lb = rb === undefined ? -1 : rb.last;
            if (la !== lb)
                return lb - la;
            // Same moment (or both never launched): the decayed score decides,
            // then the natural order.
            return root.frecencyValue(b.id) - root.frecencyValue(a.id);
        });
        return out;
    }

    function noteLaunch(entry: var): void {
        const rec = root.frecency[entry.id];
        const next = Object.assign({}, root.frecency);
        next[entry.id] = {
            "count": (rec === undefined ? 0 : rec.count) + 1,
            "last": Date.now()
        };
        root.frecency = next;
        frecencySave.running = false;
        frecencySave.json = JSON.stringify(next);
        frecencySave.running = true;
    }

    // ---- results -------------------------------------------------------
    // Every mode builds the same plain row objects, so the delegate and
    // activate() never branch on which properties a source object happens to
    // have (a DesktopEntry lacks the fields a synthetic row has, and reading a
    // missing property on it is a ReferenceError):
    //
    //   { kind: "app" | "power" | "math" | "clip",
    //     name, detail,          // the two text columns
    //     icon, glyph,           // icon name, or a nerd font glyph instead
    //     confirm,               // destructive: Enter arms, Enter again runs
    //     source }               // what activate() needs: entry, command,
    //                            // result text or clipboard line
    function makeRow(kind: string, name: string, detail: string, icon: string,
                     glyph: string, confirm: bool, source: var): var {
        return {
            "kind": kind,
            "name": name,
            "detail": detail,
            "icon": icon,
            "glyph": glyph,
            "confirm": confirm,
            "source": source
        };
    }

    readonly property var results: {
        const out = [];

        // The calculator row goes above everything else; Enter copies it.
        const math = root.evalMath(root.query);
        if (math !== null)
            out.push(root.makeRow("math", "= " + math.text, "copy to clipboard", "",
                                  "", false, math.text));

        if (root.mode === "clipboard") {
            const needle = root.query.toLowerCase();
            for (const line of root.clipboardLines) {
                if (needle === "" || line.toLowerCase().indexOf(needle) !== -1)
                    out.push(root.makeRow("clip", line, "", "", "", false, line));
            }
            return out;
        }

        // Applications rank as they always did...
        const apps = root.query === ""
            ? root.byFrecency(root.applications)
            : Fuzzy.rank(root.query, root.applications, app => root.appFields(app),
                         app => Math.min(8, root.frecencyValue(app.id)));
        for (const app of apps)
            out.push(root.makeRow("app", app.name, app.genericName, app.icon, "",
                                  false, app));

        // ...and the session actions sit below them as a block, so an
        // ambiguous query still leads with real applications. An empty query
        // keeps their natural order (Lock first), a typed one ranks the group
        // by itself so "reboot" leads with Reboot.
        for (const action of Fuzzy.rank(root.query, root.powerActions,
                                        a => root.powerFields(a)))
            out.push(root.makeRow("power", action.name, action.description, "",
                                  action.glyph, action.confirm, action.command));

        return out;
    }

    readonly property var visibleResults: root.results.slice(0, root.maxResults)

    // Footer counts, split by kind: a math row is not an app and the session
    // actions are not apps either.
    readonly property string resultSummary: {
        if (root.visibleResults.length === 0)
            return "nothing matches";
        if (root.mode === "clipboard")
            return root.results.length + " entries";
        let apps = 0;
        let actions = 0;
        for (const row of root.results) {
            if (row.kind === "app")
                apps++;
            else if (row.kind === "power")
                actions++;
        }
        return apps + " apps" + (actions > 0 ? " + " + actions + " actions" : "");
    }

    function move(delta: int): void {
        const count = root.visibleResults.length;
        if (count === 0)
            return;
        root.selected = Math.max(0, Math.min(count - 1, root.selected + delta));
    }

    function activate(): void {
        const rows = root.visibleResults;
        if (rows.length === 0)
            return;
        const choice = rows[root.selected];

        if (choice.kind === "clip") {
            root.pendingLine = choice.source;
            clipDecode.running = true;
            return;
        }

        if (choice.kind === "math") {
            Quickshell.clipboardText = choice.source;
            root.close();
            return;
        }

        if (choice.kind === "power") {
            // Enter arms a destructive row, the next Enter runs it. Any other
            // key or typing clears confirmArmed first (see the search field).
            if (choice.confirm && !root.confirmArmed) {
                root.confirmArmed = true;
                return;
            }
            root.close();
            root.launch(["sh", "-c", choice.source]);
            return;
        }

        root.close();
        root.noteLaunch(choice.source);
        if (choice.source.runInTerminal) {
            const argv = root.terminalArgv(choice.source);
            if (argv.length > 0)
                root.launch(["kitty", "-e"].concat(argv));
        } else {
            choice.source.execute();
        }
    }

    // Launching goes through a Process rather than Quickshell.execDetached:
    // execDetached takes a *string* command, so an array argument is coerced into
    // "kitty,-e,htop" and the launch silently does nothing (which is why Terminal=
    // entries and every session action were dead). Process.command takes the argv
    // list, so nothing has to be quoted.
    Process {
        id: runner
    }

    function launch(argv: var): void {
        runner.command = argv;
        runner.running = true;
    }

    // ---- terminal entries ---------------------------------------------
    // Terminal=true means "run this command in a terminal"; execute() ignores
    // it and would exec the command bare, which does nothing visible for a
    // curses program. kitty runs the command like the desktop entry asked.
    // Field codes (%U, %f, %i, ...) are not arguments — quickshell's Exec
    // parser already drops them, this strips any that remain.
    function terminalArgv(app: var): var {
        const src = app.command.length > 0 ? app.command : app.execString.trim().split(/\s+/);
        const out = [];
        for (let i = 0; i < src.length; i++) {
            const cleaned = src[i].replace(/%[fFuUick]/g, "").trim();
            if (cleaned !== "")
                out.push(cleaned);
        }
        return out;
    }

    // ---- inline math ---------------------------------------------------
    // A query that parses as arithmetic gets a "= result" row. Evaluation is a
    // whitelist tokenizer plus a recursive-descent parser over numbers, the
    // four operators, ^ and a few named functions — the query string is never
    // handed to eval/Function, so nothing typed here can reach JS scope. An
    // unparsable expression is just a query: it shows nothing.
    //
    // Grammar:  expr    := term (('+' | '-') term)*
    //           term    := unary (('*' | '/' | '%') unary)*
    //           unary   := ('+' | '-') unary | power
    //           power   := primary ('^' unary)?      right-assoc
    //           primary := number | '(' expr ')' | const | func '(' expr ')'

    // Numbers and operators, or null when a character has no business being in
    // an expression. Identifiers pass through here and are checked against the
    // symbol tables in mathPrimary.
    function mathTokens(src: string): var {
        const out = [];
        let i = 0;
        while (i < src.length) {
            const c = src[i];
            if (c === " ") {
                i++;
                continue;
            }
            if ((c >= "0" && c <= "9") || c === ".") {
                let j = i;
                let dots = 0;
                while (j < src.length && ((src[j] >= "0" && src[j] <= "9") || src[j] === ".")) {
                    if (src[j] === ".")
                        dots++;
                    j++;
                }
                const value = parseFloat(src.slice(i, j));
                if (dots > 1 || isNaN(value))
                    return null;
                out.push({ "t": "n", "v": value });
                i = j;
                continue;
            }
            if ((c >= "a" && c <= "z") || (c >= "A" && c <= "Z")) {
                let j = i;
                while (j < src.length && ((src[j] >= "a" && src[j] <= "z")
                        || (src[j] >= "A" && src[j] <= "Z")
                        || (src[j] >= "0" && src[j] <= "9")))
                    j++;
                out.push({ "t": "w", "v": src.slice(i, j).toLowerCase() });
                i = j;
                continue;
            }
            if ("+-*/%^()".indexOf(c) !== -1) {
                out.push({ "t": c });
                i++;
                continue;
            }
            return null;
        }
        return out;
    }

    function mathExpr(ts: var, p: var): var {
        let v = root.mathTerm(ts, p);
        if (v === null)
            return null;
        while (p.i < ts.length && (ts[p.i].t === "+" || ts[p.i].t === "-")) {
            const op = ts[p.i].t;
            p.i++;
            const r = root.mathTerm(ts, p);
            if (r === null)
                return null;
            v = op === "+" ? v + r : v - r;
        }
        return v;
    }

    function mathTerm(ts: var, p: var): var {
        let v = root.mathUnary(ts, p);
        if (v === null)
            return null;
        while (p.i < ts.length && (ts[p.i].t === "*" || ts[p.i].t === "/" || ts[p.i].t === "%")) {
            const op = ts[p.i].t;
            p.i++;
            const r = root.mathUnary(ts, p);
            if (r === null)
                return null;
            v = op === "*" ? v * r : op === "/" ? v / r : v % r;
        }
        return v;
    }

    function mathUnary(ts: var, p: var): var {
        if (p.i < ts.length && (ts[p.i].t === "-" || ts[p.i].t === "+")) {
            const op = ts[p.i].t;
            p.i++;
            const v = root.mathUnary(ts, p);
            return v === null ? null : (op === "-" ? -v : v);
        }
        return root.mathPower(ts, p);
    }

    function mathPower(ts: var, p: var): var {
        const base = root.mathPrimary(ts, p);
        if (base === null)
            return null;
        if (p.i < ts.length && ts[p.i].t === "^") {
            p.i++;
            // Right-associative, and the exponent may be unary (2^-1).
            const exp = root.mathUnary(ts, p);
            return exp === null ? null : Math.pow(base, exp);
        }
        return base;
    }

    function mathPrimary(ts: var, p: var): var {
        if (p.i >= ts.length)
            return null;
        const tok = ts[p.i];
        if (tok.t === "n") {
            p.i++;
            return tok.v;
        }
        if (tok.t === "(") {
            p.i++;
            const v = root.mathExpr(ts, p);
            if (v === null || p.i >= ts.length || ts[p.i].t !== ")")
                return null;
            p.i++;
            return v;
        }
        if (tok.t === "w") {
            const name = tok.v;
            p.i++;
            const c = root.mathConst(name);
            if (c !== null)
                return c;
            // Not a constant: it must be one of the whitelisted functions,
            // called with exactly one argument.
            if (p.i >= ts.length || ts[p.i].t !== "(")
                return null;
            p.i++;
            const arg = root.mathExpr(ts, p);
            if (arg === null || p.i >= ts.length || ts[p.i].t !== ")")
                return null;
            p.i++;
            return root.mathCall(name, arg);
        }
        return null;
    }

    // The two symbol tables, as switches: only these names parse, anything
    // else makes the expression invalid and the query stays a query. log is
    // the common logarithm (log(100) = 2), ln the natural one.
    function mathConst(name: string): var {
        switch (name) {
        case "pi": return Math.PI;
        case "e": return Math.E;
        default: return null;
        }
    }

    function mathCall(name: string, arg: real): var {
        switch (name) {
        case "sqrt": return Math.sqrt(arg);
        case "sin": return Math.sin(arg);
        case "cos": return Math.cos(arg);
        case "tan": return Math.tan(arg);
        case "abs": return Math.abs(arg);
        case "exp": return Math.exp(arg);
        case "ln": return Math.log(arg);
        case "log": return Math.log(arg) / Math.LN10;
        case "log2": return Math.log(arg) / Math.LN2;
        case "floor": return Math.floor(arg);
        case "ceil": return Math.ceil(arg);
        case "round": return Math.round(arg);
        default: return NaN;
        }
    }

    // Twelve significant digits, trailing zeros trimmed: sqrt(2) reads
    // 1.41421356237 instead of 1.4142135623730951.
    function mathFormat(v: real): string {
        if (Number.isInteger(v) && Math.abs(v) < 1e15)
            return String(v);
        const s = v.toPrecision(12);
        // Exponent notation just prints as JS would.
        if (s.indexOf("e") !== -1)
            return String(v);
        return s.replace(/0+$/, "").replace(/\.$/, "");
    }

    // Returns {value, text} or null. "Looks like arithmetic" needs a digit and
    // an operator, paren or name — a bare number ("2048", "7") is somebody
    // looking for an application, not a calculation.
    function evalMath(query: string): var {
        if (query === "")
            return null;
        let hasDigit = false;
        let hasShape = false;
        for (let i = 0; i < query.length; i++) {
            const c = query[i];
            if (c >= "0" && c <= "9")
                hasDigit = true;
            else if ("+-*/%^()".indexOf(c) !== -1 || (c >= "a" && c <= "z")
                     || (c >= "A" && c <= "Z"))
                hasShape = true;
        }
        if (!hasDigit || !hasShape)
            return null;

        const ts = root.mathTokens(query);
        if (ts === null || ts.length === 0)
            return null;

        const p = { "i": 0 };
        const value = root.mathExpr(ts, p);
        // Trailing tokens, a failed parse or 1/0 all show nothing.
        if (value === null || p.i !== ts.length || !isFinite(value))
            return null;

        return { "value": value, "text": root.mathFormat(value) };
    }

    // ---- clipboard -----------------------------------------------------
    Process {
        id: clipList

        command: ["cliphist", "list"]
        stdout: StdioCollector {
            id: clipListOut

            waitForEnd: true
            onStreamFinished: root.clipboardLines = clipListOut.text.split("\n").filter(line => line.trim() !== "")
        }
    }

    Process {
        id: clipDecode

        // cliphist decode takes the "id<TAB>preview" line on stdin, which is why
        // the line is passed as an argv element rather than interpolated into a
        // shell string — clipboard contents must never be parsed as shell code.
        command: ["sh", "-c", "printf %s \"$1\" | cliphist decode", "sh", root.pendingLine]
        stdout: StdioCollector {
            id: clipDecodeOut

            waitForEnd: true
            onStreamFinished: {
                // Writing clipboardText puts it on the wayland clipboard; wl-copy
                // is no longer needed for this path.
                Quickshell.clipboardText = clipDecodeOut.text;
                root.close();
            }
        }
    }

    // ---- frecency -----------------------------------------------------
    // Read once at startup; the file is created empty if missing and a corrupt
    // or unparseable file degrades to "no history" instead of an error.
    Process {
        id: frecencyLoad

        command: ["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && touch \"$1\" && cat \"$1\"", "sh", Quickshell.statePath("launcher-frecency.json")]
        running: true

        stdout: StdioCollector {
            id: frecencyLoadOut

            waitForEnd: true
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(frecencyLoadOut.text);
                    root.frecency = (parsed !== null && typeof parsed === "object") ? parsed : {};
                } catch (e) {
                    root.frecency = {};
                }
            }
        }
    }

    // Written on every launch. json is assigned first, then the process is
    // restarted so the command binding picks the new payload up.
    Process {
        id: frecencySave

        property string json: "{}"
        command: ["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf %s \"$2\" > \"$1\"", "sh", Quickshell.statePath("launcher-frecency.json"), frecencySave.json]
    }

    IpcHandler {
        target: "launcher"

        function openApps(): void {
            root.open("apps");
        }
        function openClipboard(): void {
            root.open("clipboard");
        }
        function toggleApps(): void {
            root.toggle("apps");
        }
        function close(): void {
            root.close();
        }

    }

    LazyLoader {
        active: root.showing

        PanelWindow {
            id: window

            screen: Util.focusedScreen()
            anchors.top: true
            anchors.left: true
            anchors.right: true
            anchors.bottom: true
            color: "transparent"
            // Full-screen, so it takes the whole input region while open; the
            // exclusive zone stays untouched.
            exclusiveZone: -1
            // Typing has to reach the search field, so this one *does* take
            // keyboard focus — unlike every other window in the shell.
            WlrLayershell.namespace: "quickshell-launcher"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            Rectangle {
                anchors.fill: parent
                color: Theme.alpha("#000000", 0.35)

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.close()
                }
            }

            Rectangle {
                id: card

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: 720
                implicitHeight: content.implicitHeight + 28
                // The design language's card radius: 14, generous.
                radius: 14
                color: root.cardBg
                border.width: 1
                // Hairline border in translucent purple.
                border.color: Theme.alpha(Theme.purple, 0.35)

                // Clicks inside the card must not dismiss.
                MouseArea {
                    anchors.fill: parent
                }

                Column {
                    id: content

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 14
                    spacing: 10

                    RowLayout {
                        width: parent.width
                        spacing: 10

                        Text {
                            text: root.mode === "clipboard" ? "\uf0ea" : "\uf002"
                            color: Theme.purple
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                        }

                        TextInput {
                            id: search

                            Layout.fillWidth: true
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            focus: true
                            selectByMouse: true
                            clip: true

                            // The placeholder doubles as the mode indicator.
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.mode === "clipboard" ? "search clipboard history" : "search applications"
                                color: Theme.comment
                                font: search.font
                                visible: search.text === ""
                            }

                            onTextChanged: {
                                root.query = text;
                                root.selected = 0;
                                // Typing disarms a pending confirmation.
                                root.confirmArmed = false;
                            }

                            // Any other key disarms a pending confirmation too.
                            // Return/Enter/Up/Down/Esc never reach this handler:
                            // their specific handlers below run first and accept
                            // the key, so Enter alone can arm and run.
                            Keys.onPressed: () => root.confirmArmed = false

                            Keys.onUpPressed: {
                                root.confirmArmed = false;
                                root.move(-1);
                            }
                            Keys.onDownPressed: {
                                root.confirmArmed = false;
                                root.move(1);
                            }
                            Keys.onReturnPressed: root.activate()
                            Keys.onEnterPressed: root.activate()
                            Keys.onEscapePressed: root.close()
                        }

                        // Small pill with the active mode.
                        Rectangle {
                            radius: 8
                            color: Theme.alpha(Theme.purple, 0.15)
                            border.width: 1
                            border.color: Theme.alpha(Theme.purple, 0.35)
                            implicitWidth: modeChipLabel.implicitWidth + 18
                            implicitHeight: modeChipLabel.implicitHeight + 8

                            Text {
                                id: modeChipLabel

                                anchors.centerIn: parent
                                text: root.mode === "clipboard" ? "clipboard" : "apps"
                                color: Theme.purple
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                            }
                        }
                    }

                    // The one gradient flourish on this surface: purple →
                    // pink → cyan hairline under the search row.
                    Rectangle {
                        width: parent.width
                        height: 2
                        radius: 1

                        gradient: Gradient {
                            orientation: Gradient.Horizontal

                            GradientStop {
                                position: 0.0
                                color: Theme.purple
                            }
                            GradientStop {
                                position: 0.5
                                color: Theme.pink
                            }
                            GradientStop {
                                position: 1.0
                                color: Theme.cyan
                            }
                        }
                    }

                    ListView {
                        id: list

                        width: parent.width
                        // Fixed height so the wheel scrolls the list instead of the
                        // card growing to fit hundreds of clipboard entries.
                        height: Math.min(contentHeight, root.visibleRows * root.rowHeight)
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: root.visibleResults

                        // Keyboard navigation has to drag the view along, or the
                        // selection walks off the bottom.
                        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                        currentIndex: root.selected

                        delegate: Rectangle {
                            id: row

                            required property var modelData
                            required property int index

                            readonly property bool current: index === root.selected
                            // An armed destructive row shows the second-Enter
                            // warning in the detail column.
                            readonly property bool confirming: row.current && root.confirmArmed

                            width: list.width
                            height: root.rowHeight
                            radius: 8
                            color: row.current ? Theme.alpha(Theme.selection, 0.55)
                                              : (rowMouse.containsMouse ? Theme.alpha(Theme.selection, 0.25) : "transparent")
                            Behavior on color {
                                ColorAnimation {
                                    duration: Theme.animationFast
                                }
                            }

                            // Selection marker: 3px purple left bar; the row
                            // content indents slightly around it.
                            Rectangle {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: 3
                                height: row.height - 12
                                radius: 2
                                color: Theme.purple
                                visible: row.current
                            }

                            // An application icon where there is one; rows
                            // without an icon carry a glyph (the session
                            // actions, the math row) or nothing at all.
                            Item {
                                id: iconSlot

                                anchors.left: parent.left
                                anchors.leftMargin: row.current ? 14 : 10
                                anchors.verticalCenter: parent.verticalCenter
                                width: icon.visible || glyph.visible ? 22 : 0
                                height: 22

                                Image {
                                    id: icon

                                    anchors.fill: parent
                                    sourceSize.width: 22
                                    sourceSize.height: 22
                                    visible: row.modelData.icon !== ""
                                    source: row.modelData.icon !== "" ? Quickshell.iconPath(row.modelData.icon, true) : ""
                                    fillMode: Image.PreserveAspectFit
                                }

                                Text {
                                    id: glyph

                                    anchors.centerIn: parent
                                    visible: row.modelData.glyph !== ""
                                    text: row.modelData.glyph
                                    color: row.current ? Theme.fg : Theme.alpha(Theme.comment, 0.9)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 17
                                }
                            }

                            Text {
                                id: label

                                anchors.left: iconSlot.right
                                anchors.leftMargin: iconSlot.width > 0 ? 10 : (row.current ? 14 : 10)
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.right: detail.left
                                anchors.rightMargin: 10
                                text: row.modelData.name
                                elide: Text.ElideRight
                                // The selection reads brighter than the rest.
                                color: row.current ? Theme.fg : Theme.alpha(Theme.fg, 0.85)
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                            }

                            Text {
                                id: detail

                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                width: 240
                                horizontalAlignment: Text.AlignRight
                                text: row.confirming ? "press enter again to confirm" : row.modelData.detail
                                elide: Text.ElideRight
                                // Detail column stays dimmed, the name reads
                                // first; the armed warning is pink.
                                color: row.confirming ? Theme.pink : Theme.alpha(Theme.comment, 0.8)
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                            }

                            MouseArea {
                                id: rowMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: root.selected = row.index
                                onClicked: {
                                    root.selected = row.index;
                                    root.activate();
                                }
                            }
                        }
                    }

                    RowLayout {
                        width: parent.width

                        Text {
                            text: root.resultSummary
                            color: Theme.comment
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        Text {
                            text: "↵ run   ↑↓ move   esc close"
                            color: Theme.comment
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                }
            }
        }
    }
}
