import QtQuick
import qs

// Sparkline for a 0-100 metric, drawn from Stats' history arrays.
//
// Canvas rather than a row of Rectangles: one paint per sample instead of one
// item per sample, and the fill under the line comes for free.
Canvas {
    id: root

    property var values: []
    property color lineColour: Theme.purple
    property real scaleMax: 100

    implicitWidth: 180
    implicitHeight: 30

    onValuesChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onLineColourChanged: requestPaint()

    function yFor(value: real): real {
        const clamped = Math.max(0, Math.min(root.scaleMax, value));
        return height - clamped / root.scaleMax * height;
    }

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();

        const samples = root.values;
        const count = samples.length;
        if (count < 2)
            return;

        const step = width / (count - 1);

        ctx.beginPath();
        ctx.moveTo(0, height);
        for (let i = 0; i < count; i++)
            ctx.lineTo(i * step, yFor(samples[i]));
        ctx.lineTo(width, height);
        ctx.closePath();
        ctx.fillStyle = Qt.rgba(root.lineColour.r, root.lineColour.g, root.lineColour.b, 0.15);
        ctx.fill();

        ctx.beginPath();
        for (let i = 0; i < count; i++) {
            const x = i * step;
            const y = yFor(samples[i]);
            if (i === 0)
                ctx.moveTo(x, y);
            else
                ctx.lineTo(x, y);
        }
        ctx.strokeStyle = root.lineColour;
        ctx.lineWidth = 1.5;
        ctx.lineJoin = "round";
        ctx.stroke();
    }
}
