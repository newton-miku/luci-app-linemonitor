// Chart.js 这一层照搬旧看板（deploy/www/lm/line.html）已经调好的行为，
// 只把「谁来调」换成 React：断线、部分丢包虚线、失败红点、缩放边界都保持原样。
import {
  Chart,
  LineController,
  LineElement,
  PointElement,
  BarController,
  BarElement,
  CategoryScale,
  LinearScale,
  TimeScale,
  Tooltip,
  Legend,
  Filler,
} from 'chart.js';
import 'chartjs-adapter-date-fns';
import zoomPlugin from 'chartjs-plugin-zoom';

Chart.register(
  LineController, LineElement, PointElement,
  BarController, BarElement,
  CategoryScale, LinearScale, TimeScale,
  Tooltip, Legend, Filler, zoomPlugin
);

export const C_PRIMARY = '#1668dc';
export const C_SUCCESS = '#49aa19';
export const C_WARNING = '#d89614';
export const C_ERROR = '#dc4446';
export const C_TEXT = 'rgba(255,255,255,.85)';
export const C_TEXT_2 = 'rgba(255,255,255,.45)';
export const C_GRID = '#262626';
export const C_PANEL = '#1f1f1f';

// AntV G2 的默认分类色，跟 antd 的图例观感对得上
export const PALETTE = [
  '#5B8FF9', '#5AD8A6', '#F6BD16', '#E86452', '#6DC8EC',
  '#945FB9', '#FF9845', '#1E9493', '#FF99C3', '#269A99', '#9270CA',
];

export const BAR_COLORS = [
  'rgba(91,143,249,.85)', 'rgba(90,216,166,.85)', 'rgba(246,189,22,.85)',
  'rgba(232,100,82,.85)', 'rgba(109,200,236,.85)', 'rgba(148,95,185,.85)',
];

// 判「部分丢包」的门槛：ICMP 记的是丢包百分比（三包丢一包 = 33），
// HTTP 记的是 0/1 标志位。按 >0 判会把 HTTP 的正常样本全画成虚线，
// 所以卡在 10%——真机上有 531 个点就是这么被误判的。
const LOSSY_MIN_PCT = 10;

const keyOf = (prefix, target) => `${prefix}|${target}`;
export const v4Key = (iface, t) => keyOf(iface, t);
export const v6Key = (iface, t) => keyOf('v6-' + iface, t);

function isLossy(p) {
  if (!p || p.y === null || p.y === undefined) return false;
  const l = Number(p.loss) || 0;
  return l >= LOSSY_MIN_PCT && l < 100;
}

// 每条曲线配一个「失败点」散点集：把这些点钉在 0 处，
// 曲线本身在那个位置因为 y=null 断开（spanGaps:false 才生效）。
// 散点集不进图例，跟着主线一起显隐。
export function buildLineDatasets(hist, targets, prefix, hidden) {
  const ds = [];
  const span = hist.length ? { min: hist[0].ts * 1000, max: hist[hist.length - 1].ts * 1000 } : null;
  targets.forEach((t, i) => {
    const key = keyOf(prefix, t);
    const color = PALETTE[i % PALETTE.length];
    const line = [];
    const fails = [];
    for (const rec of hist) {
      const s = rec.series[key];
      if (!s) continue;
      const x = rec.ts * 1000;
      if (s.value === null || s.value === undefined) {
        line.push({ x, y: null, loss: 100 });
        fails.push({ x, y: 0 });
      } else {
        line.push({ x, y: s.value, loss: s.loss || 0 });
      }
    }
    const off = hidden.has(t);
    ds.push({
      label: t,
      data: line,
      borderColor: color,
      backgroundColor: color,
      borderWidth: 1.5,
      pointRadius: 0,
      pointHoverRadius: 4,
      tension: 0.15,
      spanGaps: false,
      hidden: off,
      // 段级线型：这一段两头只要有一头是「部分丢包」就画成虚线。
      // v6 平时就是虚线，丢包时换成更密的虚线，两种信息都不丢。
      segment: {
        borderDash: (ctx) => {
          if (ctx.p0.skip || ctx.p1.skip) return undefined;
          const lossy = isLossy(ctx.p0.raw) || isLossy(ctx.p1.raw);
          if (lossy) return prefix.startsWith('v6-') ? [2, 3] : [5, 4];
          return prefix.startsWith('v6-') ? [5, 4] : [];
        },
      },
    });
    ds.push({
      label: t + '\u0000fail',
      data: fails,
      showLine: false,
      borderColor: C_ERROR,
      backgroundColor: C_ERROR,
      pointRadius: 2.5,
      pointHoverRadius: 4,
      hidden: off,
    });
  });
  return { ds, span };
}

export function lineOptions({ span, smooth, minRange = 60000 }) {
  return {
    responsive: true,
    maintainAspectRatio: false,
    animation: false,
    interaction: { mode: 'nearest', axis: 'x', intersect: false },
    scales: {
      x: {
        type: 'time',
        min: span ? span.min : undefined,
        max: span ? span.max : undefined,
        time: { tooltipFormat: 'MM-dd HH:mm:ss', displayFormats: { minute: 'HH:mm', hour: 'MM-dd HH:mm' } },
        grid: { color: C_GRID, drawTicks: false },
        border: { color: C_GRID },
        ticks: { color: C_TEXT_2, maxRotation: 0, autoSkipPadding: 24, font: { size: 11 } },
      },
      y: {
        beginAtZero: true,
        grid: { color: C_GRID, drawTicks: false },
        border: { color: C_GRID },
        ticks: { color: C_TEXT_2, font: { size: 11 } },
        title: { display: true, text: 'ms', color: C_TEXT_2, font: { size: 11 } },
      },
    },
    plugins: {
      // 失败散点集不进图例，否则每个目标会多出一条「xxx␀fail」
      legend: { display: false },
      tooltip: {
        backgroundColor: 'rgba(31,31,31,.95)',
        borderColor: '#424242',
        borderWidth: 1,
        titleColor: C_TEXT,
        bodyColor: C_TEXT,
        padding: 10,
        filter: (item) => !String(item.dataset.label).includes('\u0000fail'),
        callbacks: {
          label: (ctx) => {
            const raw = ctx.raw;
            const name = String(ctx.dataset.label).replace('\u0000fail', '');
            if (raw.y === null || raw.y === undefined) return `${name}: 失败`;
            const l = Number(raw.loss) || 0;
            const tail = l > 0 ? `（丢包 ${l}%）` : '';
            return `${name}: ${Math.round(raw.y)} ms${tail}`;
          },
        },
      },
      zoom: {
        pan: { enabled: true, mode: 'x', modifierKey: null },
        zoom: {
          wheel: { enabled: true, speed: 0.08 },
          pinch: { enabled: true },
          drag: { enabled: false },
          mode: 'x',
        },
        // limits 只在建图时读一次，数据变了要整条重贴（见 refreshLimits）
        limits: span ? { x: { min: span.min, max: span.max, minRange } } : {},
      },
    },
  };
}

// 数据变了之后把缩放边界重新贴上，否则新数据点会被旧的 max 挡在外面
export function refreshLimits(chart, span, minRange = 60000) {
  if (!chart || !chart.options?.plugins?.zoom) return;
  chart.options.plugins.zoom.limits = span
    ? { x: { min: span.min, max: span.max, minRange } }
    : {};
}

export function dataSpan(hist) {
  if (!hist.length) return { min: 0, max: 0 };
  return { min: hist[0].ts * 1000, max: hist[hist.length - 1].ts * 1000 };
}

export { Chart };
