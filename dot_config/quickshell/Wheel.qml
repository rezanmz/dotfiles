pragma Singleton

// Turns a wheel event into a number of steps, consistently.
//
// Stepping once per *event* is what made scrolling feel wrong: a detent can arrive
// as one event, as several, or merged with the next one, so the same flick gave
// four steps one time and five the next (measured: five notches moved the gamma by
// fifteen instead of twenty-five). Counting the *magnitude* instead — one step per
// 120 units of angleDelta, which is one detent — makes the step proportional to how
// far the wheel actually turned, no matter how the events were packed.
//
// pixelDelta is the same information in different units (a detent is about 15),
// scaled to match. Each caller passes a key so its own half-finished detent is kept
// separately: the bar, the OSD and the panel sliders must not share a remainder.
import QtQuick
import Quickshell

Singleton {
    id: root

    // 1/8 of a degree per unit; 120 units is one detent.
    readonly property real perStep: 120

    // What is left of a detent per caller.
    property var remainder: ({})

    function steps(angle: real, pixel: real, key: string): int {
        const units = angle !== 0 ? angle : pixel * 8;
        if (units === 0)
            return 0;
        const left = (root.remainder[key] !== undefined ? root.remainder[key] : 0) + units;
        let n = Math.trunc(left / root.perStep);
        // Keep the remainder, but never let it grow without bound.
        const rest = left - n * root.perStep;
        const next = {};
        for (const k in root.remainder)
            next[k] = root.remainder[k];
        next[key] = Math.max(-root.perStep, Math.min(root.perStep, rest));
        root.remainder = next;
        return n;
    }
}
