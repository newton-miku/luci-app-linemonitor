// 统计与格式化。history 里的时间戳是「秒」，窗口宽度一律用毫秒传进来。

export const WINDOWS = [
  { key: '1h', label: '1 小时', ms: 3600 * 1000 },
  { key: '6h', label: '6 小时', ms: 6 * 3600 * 1000 },
  { key: '24h', label: '24 小时', ms: 24 * 3600 * 1000 },
  { key: 'all', label: '全部', ms: 0 },
];

export function avgOf(a) {
  if (!a.length) return null;
  let s = 0;
  for (const v of a) s += v;
  return s / a.length;
}

export function sdOf(a) {
  if (a.length < 2) return null;
  const m = avgOf(a);
  let s = 0;
  for (const v of a) s += (v - m) * (v - m);
  return Math.sqrt(s / (a.length - 1));
}

// 线性插值分位，跟看板一直用的口径一致
export function pctOf(a, p) {
  if (!a.length) return null;
  const s = [...a].sort((x, y) => x - y);
  const idx = (s.length - 1) * p;
  const lo = Math.floor(idx);
  const hi = Math.ceil(idx);
  if (lo === hi) return s[lo];
  return s[lo] + (s[hi] - s[lo]) * (idx - lo);
}

// 单个目标在窗口内的统计。只看这个键真实出现过的记录，
// 免得后加的目标把早先的样本算成失败。
export function statForKey(hist, key, winMs, endTs) {
  const from = winMs ? endTs - winMs / 1000 : 0;
  const vals = [];
  let total = 0;
  let lossSum = 0;
  for (const rec of hist) {
    if (rec.ts < from) continue;
    const s = rec.series[key];
    if (!s) continue;
    total++;
    lossSum += s.loss || 0;
    if (s.value !== null && s.value !== undefined) vals.push(s.value);
  }
  return {
    total,
    ok: vals.length,
    loss: total ? lossSum / total : null,
    avg: avgOf(vals),
    p50: pctOf(vals, 0.5),
    p95: pctOf(vals, 0.95),
    p99: pctOf(vals, 0.99),
    max: vals.length ? Math.max(...vals) : null,
    sd: sdOf(vals),
  };
}

// 丢包率着色：0 不标色，1% 以下橙，1% 起红。
// 之前把 0% 也标红，纯属误报。
export function lossTxt(loss) {
  if (loss === null || loss === undefined) return '—';
  if (loss < 0.05) return '0%';
  if (loss < 1) return loss.toFixed(1) + '%';
  return Math.round(loss) + '%';
}

export function lossCls(loss) {
  if (loss === null || loss === undefined) return '';
  if (loss < 0.05) return '';
  if (loss < 1) return 'lm-warn';
  return 'lm-bad';
}

// 数值超过阈值才染色，阈值来自 config.json
export function thCls(v, warn, bad) {
  if (v === null || v === undefined) return '';
  if (bad && v >= bad) return 'lm-bad';
  if (warn && v >= warn) return 'lm-warn';
  return '';
}

export function fmtClock(ts) {
  const d = new Date(ts * 1000);
  return String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0');
}

export function fmtFull(ts) {
  const d = new Date(ts * 1000);
  const p = (n) => String(n).padStart(2, '0');
  return `${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
}

export function fmtNum(v, digits = 1) {
  if (v === null || v === undefined || Number.isNaN(v)) return '—';
  return digits === 0 ? String(Math.round(v)) : v.toFixed(digits);
}

// 最近一次成功的值（从末尾往前找）
export function lastValue(hist, key) {
  for (let i = hist.length - 1; i >= 0; i--) {
    const s = hist[i].series[key];
    if (s && s.value !== null && s.value !== undefined) return s.value;
  }
  return null;
}

export function valColor(ms) {
  if (ms === null || ms === undefined) return '#dc4446';
  if (ms < 60) return '#49aa19';
  if (ms < 120) return '#d89614';
  return '#dc4446';
}

// 把字节/秒格式化成人看的单位。速率跨度很大（空闲时几 KB、跑满时几十 MB），
// 所以用 1000 进制（网络速率的惯用进制）在 B/KB/MB/GB 之间跳。
// 小数位数随量级收：< 10 给一位，>= 10 就不给小数，免得数字一直在跳。
export function fmtRate(bps) {
  if (bps === null || bps === undefined || !Number.isFinite(bps)) return '—';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let x = Math.max(0, Number(bps));
  let i = 0;
  while (x >= 1000 && i < units.length - 1) {
    x /= 1000;
    i++;
  }
  const digits = i === 0 ? 0 : x < 10 ? 1 : 0;
  return x.toFixed(digits) + ' ' + units[i] + '/s';
}
