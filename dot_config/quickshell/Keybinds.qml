pragma Singleton

// Keybind cheatsheet data: the Hyprland binds file, parsed at runtime.
//
// Named Keybinds, not Keys, deliberately: a root-level Keys.qml would shadow
// QtQuick's `Keys` attached object (`Keys.onPressed` in Switcher.qml and
// Launcher.qml) for every document importing `qs`, because module imports rank
// above directory imports and `import qs` comes after `import QtQuick` there.
// The panel keeps the short name (panels/Keys.qml) because its type only ever
// reaches sibling documents through the implicit directory import, which ranks
// *below* module imports — see "Importing QML Document Directories".
//
// The binds live in dot_config/hypr/modules/60-binds.lua — commented Lua that
// the shell otherwise knows nothing about. A hand-copied cheatsheet drifts from
// it the first time a chord moves (the capture trio already pushed the
// move-to-workspace family onto SUPER+CTRL); this reads the file the compositor
// runs and shows what is actually bound.
//
// The file is regular enough to read without a Lua interpreter: one statement
// per line, chords and commands assembled from string literals and `..`
// concatenation through a handful of plain locals (`local mainMod = "SUPER"`),
// and one counted loop that stamps out the workspace families. The reader
// understands exactly that shape and yields nothing for anything else, so a
// future exotic bind shows up missing rather than wrong.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // [{chord, description, command, section, line}] in file order. The
    // description is the comment line the file carries above the bind, or ""
    // when there is none — the panel then shows the command instead, because
    // an invented description is worse than none.
    property var entries: []

    FileView {
        id: bindsFile

        // The copy Hyprland actually runs (chezmoi keeps source and applied
        // file identical).
        path: Quickshell.env("HOME") + "/.config/hypr/modules/60-binds.lua"
        blockLoading: true
    }

    Component.onCompleted: root.reload()

    function reload(): void {
        root.entries = parseBinds(bindsFile.text());
    }

    // ---- reader -------------------------------------------------------

    // The text of a `--` comment without the dashes, or null for a code line.
    function commentText(line: string): var {
        const m = line.match(/^\s*--(.*)$/);
        return m === null ? null : m[1];
    }

    function has(o: var, k: string): bool {
        return Object.prototype.hasOwnProperty.call(o, k);
    }

    // One side of a `..` chain: a "literal", a name, `name % n`, or a plain
    // number. Anything else is not understood and yields null.
    function evalTerm(term: string, env: var): var {
        term = term.trim();
        let m = term.match(/^"(.*)"$/);
        if (m !== null)
            return m[1];
        m = term.match(/^(\w+)\s*%\s*(\d+)$/);
        if (m !== null && has(env, m[1]))
            return String(env[m[1]] % Number(m[2]));
        if (/^\d+$/.test(term))
            return term;
        if (/^\w+$/.test(term) && has(env, term))
            return String(env[term]);
        return null;
    }

    // Split `a .. b .. c` at the concatenation dots outside string literals.
    function splitConcat(expr: string): var {
        const parts = [];
        let cur = "", quoted = false;
        for (let i = 0; i < expr.length; i++) {
            const ch = expr[i];
            if (ch === "\"")
                quoted = !quoted;
            if (!quoted && ch === "." && expr[i + 1] === ".") {
                parts.push(cur);
                cur = "";
                i++;
                continue;
            }
            cur += ch;
        }
        parts.push(cur);
        return parts;
    }

    // Evaluate a string expression, or null when the reader does not
    // understand it.
    function evalString(expr: string, env: var): var {
        let out = "";
        for (const part of splitConcat(expr)) {
            const v = evalTerm(part, env);
            if (v === null)
                return null;
            out += v;
        }
        return out;
    }

    // Text between the parenthesis at `open` and its match.
    function parenInner(s: string, open: int): string {
        let depth = 0, quoted = false;
        for (let i = open; i < s.length; i++) {
            const ch = s[i];
            if (ch === "\"")
                quoted = !quoted;
            if (quoted)
                continue;
            if (ch === "(")
                depth++;
            if (ch === ")") {
                depth--;
                if (depth === 0)
                    return s.slice(open + 1, i);
            }
        }
        return s.slice(open + 1);
    }

    // Comma-separated arguments at the top level of a call, so the third
    // `hl.bind` argument (`{ locked = true, repeating = true }`) stays one
    // piece.
    function splitArgs(s: string): var {
        const out = [];
        let cur = "", depth = 0, quoted = false;
        for (let i = 0; i < s.length; i++) {
            const ch = s[i];
            if (ch === "\"")
                quoted = !quoted;
            if (!quoted) {
                if (ch === "(" || ch === "{" || ch === "[")
                    depth++;
                if (ch === ")" || ch === "}" || ch === "]")
                    depth--;
                if (ch === "," && depth === 0) {
                    out.push(cur);
                    cur = "";
                    continue;
                }
            }
            cur += ch;
        }
        out.push(cur);
        return out.map(x => x.trim());
    }

    // Fill loop variables into dispatcher arguments so `{ workspace = i }`
    // reads `{ workspace = 1 }` — enough to see which workspace the row means.
    function substVars(s: string, env: var): string {
        for (const name of Object.keys(env))
            s = s.replace(new RegExp("\\b" + name + "\\b", "g"), String(env[name]));
        return s;
    }

    // What the bind runs, elided and never invented: the shell command behind
    // exec_cmd (locals resolved: `kitty yazi`, `qs ipc call launcher
    // toggleApps`), the dispatcher call with its arguments for the dispatchers
    // (`focus({ direction = "left" })`), or the Lua callback name for the two
    // binds that arm a confirmation.
    function commandOf(action: string, env: var): string {
        action = action.trim();
        if (action.indexOf("hl.dsp.exec_cmd(") === 0) {
            const inner = parenInner(action, "hl.dsp.exec_cmd".length);
            const s = evalString(inner, env);
            return Util.elide(s === null ? inner : s, 56);
        }
        const m = action.match(/^hl\.dsp\.(.+)$/);
        if (m !== null)
            return Util.elide(substVars(m[1], env), 56);
        return Util.elide(action, 56);
    }

    // The comment block covering the bind above `anchor`: blank lines and
    // sibling binds do not break a block (one block routinely introduces a
    // whole family, like the capture trio), any other code does. The
    // description is the block's last non-empty comment line, stripped of its
    // dashes; "" when the bind has no comment above it.
    function describe(lines: var, anchor: int): string {
        let i = anchor - 1;
        while (i >= 0) {
            const t = lines[i].trim();
            if (t === "" || t.startsWith("hl.bind(")) {
                i--;
                continue;
            }
            if (commentText(lines[i]) === null)
                return "";
            let j = i;
            while (j >= 0 && commentText(lines[j]) !== null)
                j--;
            let desc = "";
            for (let k = j + 1; k <= i; k++) {
                const c = commentText(lines[k]).trim();
                if (c !== "")
                    desc = c;
            }
            return desc;
        }
        return "";
    }

    // ---- parse ---------------------------------------------------------

    function parseBinds(text: string): var {
        const lines = text.split("\n");
        // Everything `local` defines, plus the loop counters; loop scopes are
        // copies, so a body-local (`local key = i % 10`) never leaks out.
        const env = {};
        const out = [];
        // `-- ---- Section ----` headings if the file ever grows them; absent
        // today, so rows group by the first word of the command instead.
        let heading = "";

        // The `end` closing the counted loop at `from`.
        function loopEnd(from: int): int {
            let depth = 1;
            for (let i = from + 1; i < lines.length; i++) {
                const t = lines[i].trim();
                if (commentText(lines[i]) !== null)
                    continue;
                if (/^(for|while|repeat)\b/.test(t) || /\bfunction\b/.test(t) || /\bdo\s*$/.test(t))
                    depth++;
                if (/^end\b/.test(t)) {
                    depth--;
                    if (depth === 0)
                        return i;
                }
            }
            return lines.length - 1;
        }

        function run(from: int, to: int, scope: var, anchor: int): void {
            for (let i = from; i <= to; i++) {
                const raw = lines[i];
                const t = raw.trim();
                const cm = commentText(raw);

                if (cm !== null) {
                    // A `-- ---- Section ----` line groups the rows below it.
                    const h = cm.trim().match(/^-{2,}\s*(.+?)\s*-{2,}$/);
                    if (h !== null)
                        heading = h[1].trim();
                    continue;
                }
                if (t === "")
                    continue;

                // `for i = 1, 10 do`: run the body once per value. The whole
                // loop shares the comment block above the `for`, which is where
                // the family is explained.
                const forM = t.match(/^for\s+(\w+)\s*=\s*(\d+)\s*,\s*(\d+)\s+do$/);
                if (forM !== null) {
                    const end = loopEnd(i);
                    for (let v = Number(forM[2]); v <= Number(forM[3]); v++) {
                        const child = Object.assign({}, scope);
                        child[forM[1]] = v;
                        run(i + 1, end - 1, child, i);
                    }
                    i = end;
                    continue;
                }

                // `local name = <string expr>`: the chord/command vocabulary
                // (mainMod, terminal, launcher, ...) and the loop's `key`.
                const locM = raw.match(/^\s*local\s+(\w+)\s*=\s*(.+?)\s*$/);
                if (locM !== null) {
                    const v = evalTerm(locM[2], scope);
                    if (v !== null)
                        scope[locM[1]] = v;
                    continue;
                }

                // Commented-out binds are comments and were skipped above.
                if (t.startsWith("hl.bind(")) {
                    const open = raw.indexOf("(", raw.indexOf("hl.bind"));
                    const args = splitArgs(parenInner(raw, open));
                    const chord = evalString(args[0], scope);
                    if (chord === null)
                        continue;
                    const cmd = commandOf(args.length > 1 ? args[1] : "", scope);
                    out.push({
                        "chord": chord.replace(/\s+/g, " ").trim(),
                        "description": describe(lines, anchor >= 0 ? anchor : i),
                        "command": cmd,
                        "section": heading !== "" ? heading : (cmd.match(/^[A-Za-z0-9_-]+/) || ["?"])[0],
                        "line": i + 1
                    });
                }
            }
        }

        run(0, lines.length - 1, env, -1);
        return out;
    }
}
