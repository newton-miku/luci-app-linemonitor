// 总览页的柱状图：拿最近一次采集的每个 v4 目标，按出口并列对比。
import { useEffect, useRef } from 'react';
import { Chart, C_GRID, C_TEXT, C_TEXT_2, BAR_COLORS } from '../chart.js';

export default function BarChart({ hist, exits, targets, height = 260 }) {
  const ref = useRef(null);
  const inst = useRef(null);

  useEffect(() => {
    const last = hist.length ? hist[hist.length - 1] : null;
    const labels = targets;
    const datasets = exits.map((e, i) => ({
      label: e.label || e.if,
      data: targets.map((t) => {
        const s = last?.series[e.if + '|' + t];
        return s && s.value !== null && s.value !== undefined ? s.value : null;
      }),
      backgroundColor: BAR_COLORS[i % BAR_COLORS.length],
      borderRadius: 3,
      maxBarThickness: 34,
    }));

    const options = {
      responsive: true,
      maintainAspectRatio: false,
      animation: false,
      plugins: {
        legend: { position: 'top', labels: { color: C_TEXT, boxWidth: 12, boxHeight: 12, font: { size: 12 } } },
        tooltip: {
          backgroundColor: 'rgba(31,31,31,.95)',
          borderColor: '#424242',
          borderWidth: 1,
          titleColor: C_TEXT,
          bodyColor: C_TEXT,
          callbacks: { label: (c) => `${c.dataset.label}: ${c.raw === null ? '失败' : Math.round(c.raw) + ' ms'}` },
        },
      },
      scales: {
        x: { grid: { display: false }, border: { color: C_GRID }, ticks: { color: C_TEXT_2, font: { size: 11 } } },
        y: {
          beginAtZero: true,
          grid: { color: C_GRID, drawTicks: false },
          border: { color: C_GRID },
          ticks: { color: C_TEXT_2, font: { size: 11 } },
          title: { display: true, text: 'ms', color: C_TEXT_2, font: { size: 11 } },
        },
      },
    };

    if (!inst.current) {
      inst.current = new Chart(ref.current, { type: 'bar', data: { labels, datasets }, options });
    } else {
      inst.current.data.labels = labels;
      inst.current.data.datasets = datasets;
      inst.current.update('none');
    }
    return undefined;
  }, [hist, exits, targets]);

  useEffect(() => () => { inst.current?.destroy(); inst.current = null; }, []);

  return (
    <div style={{ position: 'relative', height }}>
      <canvas ref={ref} />
    </div>
  );
}
