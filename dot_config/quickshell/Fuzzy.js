.pragma library

// Ranking for the launcher, replacing anyrun's rink plugin. Pure JS on
// purpose: the QML side only calls score()/rank(), and keeping the matcher out
// of QML means it can be exercised from a plain JS harness without spinning up
// the shell.
//
// The score is the best alignment of the query inside the target, found with a
// forward DP over the (short) query. Greedy leftmost matching looked tempting
// but scores "ab" in "a_ab" as a scattered pair when the consecutive alignment
// at the word start is sitting right there.

const BASE = 16;    // every matched character
const CONSEC = 24;  // match directly after the previous one: runs beat scatter
const WORD = 16;    // match at a word start
const GAP = 8;      // per target character skipped between two matches
const LEN = 1;      // per target character, so shorter targets win ties
const PREFIX = 32;  // the query matches from position 0
const EXACT = 64;   // target is the query (case-insensitively)
const NEG = -1e12;  // "no alignment" sentinel; real scores never get near it

// Scratch reused across calls. The library object lives as long as the shell
// and score() runs once per entry per keystroke, so per-call arrays would just
// churn the GC. Index j tracks how much of the query is consumed.
const dpScore = [];  // best score with query[j] matched at the current position
const dpHold = [];   // running max of dpScore[j] + GAP * (pos + 1) over earlier
                     // positions: turns the per-gap penalty into a lookup

// ASCII-only case test: the Unicode case tables can change string length
// ("İ".toLowerCase() is two characters) and would misalign the indices the
// word-start check borrows from the original string.
function isUpper(code) {
    return code >= 65 && code <= 90;
}

// Word starts are separator boundaries and camelCase/InitialCaps humps. The
// start of the string is deliberately NOT one (the PREFIX bonus already covers
// that) unless it opens a capitalized word — that is what makes "File Manager"
// outrank "firefox" for "fi".
// `s` is the original-cased target: case information is gone by the time the
// comparison runs on the lowered strings. Out-of-range indices (possible when
// lowering changes the length) just read NaN and fall through to false.
function isWordStart(s, i) {
    const c = s.charCodeAt(i);
    if (i === 0)
        return isUpper(c);
    const p = s.charCodeAt(i - 1);
    if (p === 45 || p === 95 || p === 32 || p === 46)  // - _ <space> .
        return true;
    if (!isUpper(c) || isUpper(p))
        return false;
    return true;  // camelCase hump, including letter-after-digit ("var2Name")
}

// -1 when the query is not a subsequence of the target, otherwise a score
// where higher is better. Case-insensitive; both strings are lowered exactly
// once per call.
function score(query, target) {
    if (!query)
        return 0;
    if (!target)
        return -1;

    const q = query.toLowerCase();
    const t = target.toLowerCase();
    const m = q.length;
    const n = t.length;
    if (m > n)
        return -1;

    for (let j = 0; j < m; j++) {
        dpScore[j] = NEG;
        dpHold[j] = NEG;
    }

    let best = NEG;
    for (let i = 0; i < n; i++) {
        const c = t.charCodeAt(i);
        const w = isWordStart(target, i) ? WORD : 0;
        // Descending j on purpose: the transitions read index j-1, and this
        // way those cells still hold position i-1 (dpScore) or earlier
        // positions (dpHold) instead of values from this same character.
        for (let j = m - 1; j >= 0; j--) {
            if (c !== q.charCodeAt(j)) {
                dpScore[j] = NEG;
                continue;
            }
            let s;
            if (j === 0) {
                // Leading unmatched characters are free; PREFIX is what
                // rewards starting the match at position 0.
                s = BASE + w + (i === 0 ? PREFIX : 0);
            } else {
                const held = dpHold[j - 1];
                const prev = dpScore[j - 1];
                if (held === NEG && prev === NEG) {
                    dpScore[j] = NEG;
                    continue;
                }
                const viaGap = held === NEG ? NEG : held - GAP * i;
                const viaConsec = prev === NEG ? NEG : prev + CONSEC;
                s = BASE + w + (viaGap > viaConsec ? viaGap : viaConsec);
            }
            dpScore[j] = s;
            const fold = s + GAP * (i + 1);
            if (fold > dpHold[j])
                dpHold[j] = fold;
        }
        if (dpScore[m - 1] > best)
            best = dpScore[m - 1];
    }

    if (best === NEG)
        return -1;
    let s = best - LEN * target.length;
    if (q === t)
        s += EXACT;
    // -1 is the documented non-match sentinel and the length penalty alone can
    // push a real match to exactly -1 on a huge target, so floor matches at 0.
    return s > 0 ? s : 0;
}

// Entries sorted best-first, non-matches dropped. keyFn(entry) is called once
// per entry. An empty query keeps the caller's order untouched — the launcher
// has a meaningful natural order that re-sorting would destroy — and ties keep
// the input order too (the comparator falls back to the original index).
function rank(query, entries, keyFn) {
    if (!query)
        return entries.slice();

    const pairs = [];
    for (let i = 0; i < entries.length; i++) {
        const s = score(query, keyFn(entries[i]));
        if (s >= 0)
            pairs.push([entries[i], s, i]);
    }
    pairs.sort((a, b) => (b[1] - a[1]) || (a[2] - b[2]));

    const out = new Array(pairs.length);
    for (let i = 0; i < pairs.length; i++)
        out[i] = pairs[i][0];
    return out;
}
