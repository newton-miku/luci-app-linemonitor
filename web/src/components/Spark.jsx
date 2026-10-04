// 迷你趋势卡里的那条细线。不画轴、不响应交互，只表达「最近这段怎么走的」。
import { useEffect, useRef } from 'react';
import { Chart, PALETTE } from '../chart.js';

export default function Spark({ hist, prefix, targets, height = 80 }) {
  const ref = useRef(null);
  const inst = useRef(null);

  useEffect(() => {
    const datasets = targets.map((t, i) => {
      const key = prefix + '|' + t.name;
      const color = PALETTE[i % PALETTE.length];
      const data = [];
      for (const rec of hist) {
        const s = rec.series[key];
        if (!s) continue;
        data.push({ x: rec.ts * 1000, y: s.value === null || s.value === undefined ? null : s.value });
      }
      return {
        label: t.name,
        data,
        borderColor: color,
        backgroundColor: color,
        borderWidth: 1,
        pointRadius: 0,
        tension: 0.2,
        spanGaps: false,
      };
    });

    const options = {
      responsive: true,
      maintainAspectRatio: false,
      animation: false,
      events: [],
      plugins: {
        legend: { display: false },
        tooltip: { enabled: false },
        zoom: {},
      },
      scales: {
        x: { type: 'time', display: false, min: hist.length ? hist[0].ts * 1000 : undefined,
             max: hist.length ? hist[hist.length - 1].ts * 1000 : undefined },
        y: { display: false, beginAtZero: true },
      },
    };

    if (!inst.current) {
      inst.current = new Chart(ref.current, { type: 'line', data: { datasets }, options });
    } else {
      inst.current.data.datasets = datasets;
      inst.current.options.scales.x.min = hist.length ? hist[0].ts * 1000 : undefined;
      inst.current.options.scales.x.max = hist.length ? hist[hist.length - 1].ts * 1000 : undefined;
      inst.current.update('none');
    }
    return undefined;
  }, [hist, prefix, targets]);

  useEffect(() => () => { inst.current?.destroy(); inst.current = null; }, []);

  return (
    <div style={{ position: 'relative', height }}>
      <canvas ref={ref} />
    </div>
  );
}
