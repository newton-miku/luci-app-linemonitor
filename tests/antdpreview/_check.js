
// ==================== 配置 ====================
const HIST_URL = 'history.log';
const TCP_URL  = 'tcp.json';
const CONFIG_URL = 'config.json';
const HIST_REFRESH = 60000;
const TCP_REFRESH  = 5000;
const LS_KEY = 'lm_visibility';
const LS_KEY_SMOOTH = 'lm_smooth';
const LS_KEY_STATWIN = 'lm_statwin';

// 内置默认值：读不到 config.json 时退回这套，保证看板永远能开
const DEFAULT_EXITS = [
  { if:'eth1',        label:'移动' },
  { if:'pppoe-wan2',  label:'电信' }
];
const DEFAULT_V4_TARGETS = ['阿里DNS','腾讯DNS','CNNIC','微信','淘宝','B站','字节','QQ'];
const DEFAULT_V6_TARGETS = ['阿里v6','腾讯v6','移动v6'];

// 出口的两个 key（第 1、第 2 个出口），由 config.json 的 exits 顺序决定
let EXIT1_KEY = 'eth1', EXIT2_KEY = 'pppoe-wan2';
let V61_KEY = 'v6-eth1', V62_KEY = 'v6-pppoe-wan2';
let V4_TARGETS = DEFAULT_V4_TARGETS.slice();
let V6_TARGETS = DEFAULT_V6_TARGETS.slice();
let EXITS = DEFAULT_EXITS.slice();

// 统计表配色阈值（毫秒），由 config.json 覆盖。只有前端用，不影响采集。
// 「最大延迟」看有没有偶发卡死，「波动σ」看这条线路稳不稳，各目标基线差异大所以要可调。
let TH_MAX_WARN = 300, TH_MAX_BAD = 1000;
let TH_SD_WARN = 50, TH_SD_BAD = 200;

// Ant Design 深色主题的语义色（success/warning/error/primary），曲线配色也照它的色板走
const C_PRIMARY = '#177ddc', C_SUCCESS = '#49aa19', C_WARNING = '#d89614', C_ERROR = '#dc4446';
const C_TEXT = 'rgba(255,255,255,.85)', C_TEXT_2 = 'rgba(255,255,255,.45)';
const C_GRID = '#303030', C_PANEL = '#1f1f1f';

const PALETTE = ['#177ddc','#49aa19','#d89614','#db2fb9','#642ab5','#13c2c2','#fa8c16','#8c8c8c','#dc4446','#2f9bd6','#a0d911'];

// 接口名 -> 看板显示名（未知接口原样返回）
function labelOf(iface) {
  if (!iface) return '';
  const hit = EXITS.find(e => e.if === iface);
  if (hit) return hit.label;
  if (iface === '未知') return '未知';
  return iface;
}
// 出口 -> antd Tag 配色。按出口序号取色，用户改成什么名字都有对应样式。
const TAG_COLORS = ['ant-tag-blue','ant-tag-green','ant-tag-gold','ant-tag-purple','ant-tag-cyan','ant-tag-magenta'];
function tagClassOf(iface) {
  const i = EXITS.findIndex(e => e.if === iface);
  return i >= 0 ? TAG_COLORS[i % TAG_COLORS.length] : '';
}

// 拉取 /www/lm/config.json（由 lm_config_json.sh 从 targets.conf 生成）
async function loadConfig() {
  try {
    const r = await fetch(CONFIG_URL + '?t=' + Date.now(), { cache: 'no-store' });
    if (!r.ok) throw new Error('HTTP ' + r.status);
    const cfg = await r.json();
    if (cfg.title) document.getElementById('dashTitle').textContent = cfg.title;
    document.title = (cfg.title || '线路质量监测看板');
    if (cfg.subtitle) document.getElementById('dashSub').textContent = cfg.subtitle;
    if (Array.isArray(cfg.exits) && cfg.exits.length) EXITS = cfg.exits;
    if (Array.isArray(cfg.targets_v4) && cfg.targets_v4.length) V4_TARGETS = cfg.targets_v4;
    if (Array.isArray(cfg.targets_v6) && cfg.targets_v6.length) V6_TARGETS = cfg.targets_v6;
    const pos = (v, d) => (typeof v === 'number' && isFinite(v) && v > 0 ? v : d);
    TH_MAX_WARN = pos(cfg.th_max_warn, TH_MAX_WARN);
    TH_MAX_BAD  = pos(cfg.th_max_bad,  TH_MAX_BAD);
    TH_SD_WARN  = pos(cfg.th_sd_warn,  TH_SD_WARN);
    TH_SD_BAD   = pos(cfg.th_sd_bad,   TH_SD_BAD);
  } catch (e) {
    console.warn('config.json 读取失败，用内置默认值:', e.message);
  }
  const e1 = EXITS[0] || DEFAULT_EXITS[0];
  const e2 = EXITS[1] || DEFAULT_EXITS[1];
  EXIT1_KEY = e1.if; EXIT2_KEY = e2.if;
  V61_KEY = 'v6-' + e1.if; V62_KEY = 'v6-' + e2.if;
  applyConfigToDom();
}

// 把配置写进静态 DOM（曲线小标题、出口下拉）
function applyConfigToDom() {
  const e1 = EXITS[0] || DEFAULT_EXITS[0];
  const e2 = EXITS[1] || DEFAULT_EXITS[1];
  const set = (id, txt) => { const el = document.getElementById(id); if (el) el.textContent = txt; };

  set('navBtn1', e1.label + '表');
  set('navBtn2', e2.label + '表');
  if (!document.getElementById('dashSub').textContent) {
    set('dashSub', labelOf(EXIT1_KEY) + ' ' + EXIT1_KEY + ' + ' + labelOf(EXIT2_KEY) + ' ' + EXIT2_KEY + ' + IPv6');
  }
  // tab 按钮的 data-tab 不变，只换文字
  const sel = document.getElementById('fIface');
  const keep = sel.value;
  sel.innerHTML = '<option value="">全部出口</option>' +
    EXITS.map(e => '<option>' + e.label + '</option>').join('') +
    '<option>未知</option>';
  sel.value = keep;
}


// ==================== 状态 ====================
let histData = [];
let tcpData = { ts:0, streams:[] };
let charts = {};
const chartState = {};   // tabKey -> { defs, visible:Set, sliderIdx, isLive }
let smoothOn = false;    // 平滑曲线开关（全局，三个曲线标签页共用）

// ==================== 工具 ====================
function pad(n) { return String(n).padStart(2,'0'); }
function fmtTime(ts) { const d = new Date(ts*1000); return pad(d.getHours())+':'+pad(d.getMinutes()); }
function fmtFull(ts) {
  const d = new Date(ts*1000);
  return pad(d.getMonth()+1)+'-'+pad(d.getDate())+' '+fmtTime(ts)+':'+pad(d.getSeconds());
}
function avg(a) { return a.length ? a.reduce((x,y)=>x+y,0)/a.length : null; }
function lastValue(key) {
  for (let i = histData.length-1; i >= 0; i--) {
    const s = histData[i].series[key];
    if (s && s.value !== null) return s.value;
  }
  return null;
}
function valAt(key, idx) {
  // 取 <= idx 的最近一个有效值（用于开关 chip 显示当前时刻的值）
  for (let i = Math.min(idx, histData.length-1); i >= 0; i--) {
    const s = histData[i].series[key];
    if (s && s.value !== null) return s.value;
  }
  return null;
}

// ==================== 解析 history.log ====================
function parseHistory(text) {
  const out = [];
  for (const line of text.split('\n')) {
    const t = line.trim();
    if (!t) continue;
    const parts = t.split(/\s+/);
    const ts = Number(parts[0]);
    if (!ts) continue;
    const series = {};
    for (let i = 1; i < parts.length; i++) {
      const m = parts[i].match(/^([^|]+)\|([^=]+)=([^,]+),(.+)$/);
      if (!m) continue;
      series[m[1] + '|' + m[2]] = {
        value: m[3] === 'FAIL' ? null : Number(m[3]),
        status: m[4]
      };
    }
    out.push({ ts, series });
  }
  return out;
}

// ==================== 失败红点 plugin ====================
// 用时间戳定位像素坐标，避免数据断点导致索引错位
const failDotPlugin = {
  id: 'failDots',
  afterDatasetsDraw(chart) {
    const ctx = chart.ctx;
    const xs = chart.scales.x, ys = chart.scales.y;
    chart.data.datasets.forEach((ds, di) => {
      if (!ds._fails || !ds._fails.length) return;
      if (!chart.isDatasetVisible(di)) return;
      ctx.save();
      ds._fails.forEach(f => {
        const px = xs.getPixelForValue(f.x);
        const py = ys.getPixelForValue(f.y);
        if (!isFinite(px) || !isFinite(py)) return;
        ctx.beginPath();
        ctx.arc(px, py, 4, 0, Math.PI*2);
        ctx.fillStyle = C_ERROR;
        ctx.fill();
        ctx.strokeStyle = '#000';
        ctx.lineWidth = 1.5;
        ctx.stroke();
      });
      ctx.restore();
    });
  }
};
Chart.register(failDotPlugin);

// ==================== 数据集构建 ====================
// endIdx: null/undefined = 全部数据（实时）；数字 = 只画到该索引（回放）
function buildDatasets(defs, endIdx) {
  const sliceAll = (endIdx === null || endIdx === undefined);
  const slice = sliceAll ? histData : histData.slice(0, endIdx + 1);
  return defs.map(def => {
    const points = [];
    const fails = [];
    let lastY = null;
    let inFail = false;
    slice.forEach(d => {
      const s = d.series[def.key];
      if (!s) return;
      if (s.value !== null) {
        points.push({ x: d.ts * 1000, y: s.value });
        lastY = s.value;
        inFail = false;
      } else if (!inFail) {
        // 连续丢包只在段起点标一个红点；y 取最近有效值，从未成功过则落底
        fails.push({ x: d.ts * 1000, y: lastY !== null ? lastY : 0 });
        inFail = true;
      }
    });
    return {
      label: def.label,
      data: points,
      borderColor: def.color,
      backgroundColor: def.color,
      borderWidth: 1.6,
      borderDash: def.dash || [],
      pointRadius: 0,
      pointHoverRadius: 4,
      pointHitRadius: 10,
      tension: smoothOn ? 0.4 : 0,
      cubicInterpolationMode: smoothOn ? 'monotone' : 'default',
      spanGaps: false,
      _color: def.color,
      _fails: fails
    };
  });
}

// ==================== 缩放边界 ====================
// 缩放/平移不许越过实际数据范围：右边界最多到最新一个采集点，左边界最多到最早一个点，
// 拖不出空白区域。
//
// 为什么不用插件自带的 limits：'original' 会把范围锁死在页面加载那一刻，之后新采集的
// 点会被挤出画面（实测数据涨到 04:02 而轴停在 03:52）；'data' 这个关键字 2.0.1 不认。
// 所以在每次缩放/平移结束后自己夹一次。
let clampingX = false;
function clampXToData(chart) {
  if (clampingX || !chart) return;
  const all = chart.data.datasets.flatMap(d => d.data.map(p => p.x));
  if (all.length < 2) return;
  const dMin = Math.min(...all), dMax = Math.max(...all);
  const xs = chart.scales.x;
  if (xs.min >= dMin && xs.max <= dMax) return;   // 已经在范围内，不用动
  let a = Math.max(xs.min, dMin);
  let b = Math.min(xs.max, dMax);
  if (b - a < 60000) { a = dMin; b = dMax; }      // 夹得比一分钟还窄就直接还原全范围
  clampingX = true;
  chart.zoomScale('x', { min: a, max: b }, 'none');
  setTimeout(() => { clampingX = false; }, 0);
}

// ==================== 折线图通用配置 ====================
function lineOptions() {
  return {
    responsive: true,
    maintainAspectRatio: false,
    animation: false,
    interaction: { mode: 'nearest', axis: 'x', intersect: false },
    plugins: {
      legend: { display: false },   // 用自绘 chip 代替
      tooltip: {
        backgroundColor: C_PANEL, borderColor: C_GRID, borderWidth: 1,
        titleColor: C_TEXT, bodyColor: 'rgba(255,255,255,.65)', padding: 10,
        callbacks: {
          title: items => items.length ? fmtFull(items[0].parsed.x / 1000) : '',
          label: item => {
            const ds = item.dataset;
            return ' ' + ds.label + ': ' + (item.parsed.y === null ? '失败' : item.parsed.y + ' ms');
          }
        }
      },
      zoom: {
        pan: {
          enabled: true, mode: 'x', modifierKey: 'shift',
          onPanComplete: ({ chart }) => clampXToData(chart)
        },
        zoom: {
          wheel: { enabled: true }, pinch: { enabled: true }, mode: 'x',
          onZoomComplete: ({ chart }) => clampXToData(chart)
        }
      }
    },
    scales: {
      x: {
        type: 'time',
        time: { tooltipFormat: 'MM-dd HH:mm:ss', displayFormats: { minute:'HH:mm', hour:'MM-dd HH:mm' } },
        ticks: { color: C_TEXT_2, maxTicksLimit: 12, font: { size: 11 }, autoSkip: true },
        grid: { color: C_GRID }
      },
      y: {
        beginAtZero: true,
        ticks: { color: C_TEXT_2, font: { size: 11 } },
        grid: { color: C_GRID },
        title: { display: true, text: 'ms', color: C_TEXT_2 }
      }
    }
  };
}

// ==================== 图表定义（每个 tab 的曲线来源）====================
function tabDefs(tabKey) {
  if (tabKey === 'wan1') {
    return V4_TARGETS.map((t, i) => ({ label: t, key: EXIT1_KEY + '|' + t, color: PALETTE[i % PALETTE.length] }));
  }
  if (tabKey === 'wan2') {
    return V4_TARGETS.map((t, i) => ({ label: t, key: EXIT2_KEY + '|' + t, color: PALETTE[i % PALETTE.length] }));
  }
  // v6: 第一个出口实线 + 第二个出口虚线，同一目标共用颜色
  const defs = [];
  const l1 = labelOf(EXIT1_KEY), l2 = labelOf(EXIT2_KEY);
  V6_TARGETS.forEach((t, i) => {
    const c = PALETTE[i % PALETTE.length];
    defs.push({ label: l1 + 'v6·' + t, key: V61_KEY + '|' + t, color: c, dash: [] });
    defs.push({ label: l2 + 'v6·' + t, key: V62_KEY + '|' + t, color: c, dash: [5,4] });
  });
  return defs;
}

// ==================== 可见性持久化 ====================
function loadVis() { try { return JSON.parse(localStorage.getItem(LS_KEY) || '{}'); } catch (e) { return {}; } }
function saveVis() {
  const o = {};
  for (const k in chartState) o[k] = [...chartState[k].visible];
  try { localStorage.setItem(LS_KEY, JSON.stringify(o)); } catch (e) {}
}

// ==================== 曲线开关 ====================
function renderToggles(tabKey) {
  const st = chartState[tabKey];
  const box = document.getElementById('toggles-' + tabKey);
  box.innerHTML = '';
  st.valEls = {};

  st.defs.forEach(def => {
    const chip = document.createElement('span');
    const shown = st.visible.has(def.label);
    chip.className = 'ant-tag ' + (shown ? '' : 'lm-off');
    const dot = document.createElement('span');
    dot.className = 'lm-dot';
    dot.style.background = def.color;
    const name = document.createElement('span');
    name.textContent = def.label;
    const val = document.createElement('span');
    val.className = 'lm-val';
    chip.append(dot, name, val);
    chip.title = '点击显示/隐藏该曲线';
    st.valEls[def.label] = val;
    chip.addEventListener('click', () => {
      if (st.visible.has(def.label)) st.visible.delete(def.label);
      else st.visible.add(def.label);
      applyVisibility(tabKey);
      renderToggles(tabKey);
      saveVis();
    });
    box.appendChild(chip);
  });

  // 全开 / 全关
  const actions = document.createElement('span');
  actions.className = 'lm-series-actions';
  const btnAll = document.createElement('button');
  btnAll.className = 'ant-btn ant-btn-sm';
  btnAll.innerHTML = '<span>全选</span>';
  btnAll.addEventListener('click', () => {
    st.defs.forEach(d => st.visible.add(d.label));
    applyVisibility(tabKey); renderToggles(tabKey); saveVis();
  });
  const btnNone = document.createElement('button');
  btnNone.className = 'ant-btn ant-btn-sm';
  btnNone.innerHTML = '<span>全不选</span>';
  btnNone.addEventListener('click', () => {
    st.visible.clear();
    applyVisibility(tabKey); renderToggles(tabKey); saveVis();
  });
  actions.append(btnAll, btnNone);
  box.appendChild(actions);

  refreshToggleValues(tabKey);
}

// 只刷新开关上的数值文本，不重建 DOM（避免打断悬停/点击）
function refreshToggleValues(tabKey) {
  const st = chartState[tabKey];
  if (!st || !st.valEls) return;
  const curIdx = st.isLive ? histData.length - 1 : st.sliderIdx;
  st.defs.forEach(def => {
    const el = st.valEls[def.label];
    if (!el) return;
    const v = valAt(def.key, curIdx);
    el.textContent = v === null ? '—' : Math.round(v) + 'ms';
  });
}

function applyVisibility(tabKey) {
  const st = chartState[tabKey];
  const chart = charts[tabKey];
  if (!chart) return;
  chart.data.datasets.forEach((ds, i) => {
    chart.setDatasetVisibility(i, st.visible.has(ds.label));
  });
  chart.update('none');
}

// ==================== 绘制 / 刷新 ====================
function drawChart(tabKey) {
  const st = chartState[tabKey];
  const endIdx = st.isLive ? null : st.sliderIdx;
  const datasets = buildDatasets(st.defs, endIdx);
  const chart = charts[tabKey];
  chart.data.datasets = datasets;
  datasets.forEach((ds, i) => chart.setDatasetVisibility(i, st.visible.has(ds.label)));
  chart.update('none');
}

// ==================== 平滑开关 ====================
// 开启后用单调三次插值画曲线：视觉圆滑，但曲线永远不会越过相邻数据点的值，
// 既不会把尖刺画得比真实更高，也不会在低点之间画到负数。
// 关掉就是折线，尖刺的陡峭程度看得最准。红点（失败标记）两种模式都不受影响。
function loadSmooth() {
  try { return localStorage.getItem(LS_KEY_SMOOTH) === '1'; } catch (e) { return false; }
}
function syncSmoothButtons() {
  ['wan1','wan2','v6'].forEach(k => {
    const btn = document.getElementById('smoothBtn-' + k);
    if (!btn) return;
    btn.classList.toggle('ant-btn-primary', smoothOn);
    btn.setAttribute('aria-pressed', smoothOn ? 'true' : 'false');
  });
}
function applySmooth() {
  syncSmoothButtons();
  ['wan1','wan2','v6'].forEach(k => { if (charts[k]) drawChart(k); });
  renderSparks();
}
function setSmooth(on) {
  smoothOn = on;
  try { localStorage.setItem(LS_KEY_SMOOTH, on ? '1' : '0'); } catch (e) {}
  applySmooth();
}

// ==================== 实时状态 ====================
function setupTimeline(tabKey) {
  const st = chartState[tabKey];
  const liveBtn = document.getElementById('liveBtn-' + tabKey);

  // 没有时间显示控件了，保留空实现给 loadHist 等调用点
  st.syncTimeline = function () {};

  function setLive(on) {
    st.isLive = on;
    liveBtn.classList.toggle('ant-btn-primary', on);
    if (on) st.sliderIdx = Math.max(0, histData.length - 1);
    st.syncTimeline();
    drawChart(tabKey);
    refreshToggleValues(tabKey);
  }
  st.setLive = setLive;

  liveBtn.addEventListener('click', () => setLive(true));
}

// ==================== 初始化一个折线标签页 ====================
function initLineTab(tabKey, canvasId) {
  const defs = tabDefs(tabKey);
  const saved = loadVis()[tabKey];
  const visible = new Set();
  defs.forEach(d => {
    if (saved && saved.length) { if (saved.includes(d.label)) visible.add(d.label); }
    else visible.add(d.label);
  });
  chartState[tabKey] = { defs, visible, sliderIdx: 0, isLive: true };

  charts[tabKey] = new Chart(document.getElementById(canvasId), {
    type: 'line',
    data: { datasets: buildDatasets(defs, null) },
    options: lineOptions()
  });
  const cv = document.getElementById(canvasId);
  // 移动端双指缩放需要触摸事件
  cv.addEventListener('touchstart', e => { if (e.touches.length > 1) e.preventDefault(); }, { passive: false });
  // 重置缩放按钮已移除，改成双击图表还原
  cv.addEventListener('dblclick', () => { charts[tabKey]?.resetZoom(); });

  applyVisibility(tabKey);
  setupTimeline(tabKey);
  renderToggles(tabKey);
}

// ==================== 统计 ====================
const STAT_WINDOWS = [
  { k:'1h',  label:'1 小时',  sec:3600 },
  { k:'6h',  label:'6 小时',  sec:21600 },
  { k:'24h', label:'24 小时', sec:86400 },
  { k:'all', label:'全部',    sec:null }
];
let statWin = '1h';

function loadStatWin() {
  try {
    const v = localStorage.getItem(LS_KEY_STATWIN);
    if (STAT_WINDOWS.some(w => w.k === v)) statWin = v;
  } catch (e) {}
}
function syncStatWinButtons() {
  document.querySelectorAll('#statBox-overview .ant-segmented-item, #statBox-wan1 .ant-segmented-item, ' +
                           '#statBox-wan2 .ant-segmented-item, #statBox-v6 .ant-segmented-item').forEach(el => {
    const on = el.dataset.w === statWin;
    el.classList.toggle('ant-segmented-item-selected', on);
    const input = el.querySelector('input');
    if (input) input.checked = on;
  });
}
function setStatWin(k) {
  statWin = k;
  try { localStorage.setItem(LS_KEY_STATWIN, k); } catch (e) {}
  renderStats();
}

// 线性插值分位数，p 取 0~1
function pctOf(sorted, p) {
  const n = sorted.length;
  if (!n) return null;
  if (n === 1) return sorted[0];
  const idx = (n - 1) * p;
  const lo = Math.floor(idx), hi = Math.ceil(idx);
  return lo === hi ? sorted[lo] : sorted[lo] + (sorted[hi] - sorted[lo]) * (idx - lo);
}

function statWindowFrom() {
  const w = STAT_WINDOWS.find(x => x.k === statWin);
  if (!w || w.sec === null || !histData.length) return 0;
  return histData[histData.length - 1].ts - w.sec;
}

// keys 可以是单个 key 字符串，也可以是数组（把多个目标合并统计）
function statFor(keys) {
  if (typeof keys === 'string') keys = [keys];
  const from = statWindowFrom();
  const vals = [];
  let records = 0, lossSum = 0;
  for (let i = 0; i < histData.length; i++) {
    const d = histData[i];
    if (d.ts < from) continue;
    for (const k of keys) {
      const s = d.series[k];
      if (!s) continue;
      records++;
      if (s.value !== null) vals.push(s.value);
      const st = Number(s.status);
      lossSum += isFinite(st) ? st : (s.value === null ? 100 : 0);
    }
  }
  vals.sort((a, b) => a - b);
  const mean = vals.length ? vals.reduce((x, y) => x + y, 0) / vals.length : null;
  let sd = null;
  if (vals.length > 1) {
    const v = vals.reduce((s, x) => s + (x - mean) * (x - mean), 0) / (vals.length - 1);
    sd = Math.sqrt(v);
  }
  return {
    records, ok: vals.length,
    loss: records ? lossSum / records : null,
    avg: mean, p50: pctOf(vals, .50), p95: pctOf(vals, .95), p99: pctOf(vals, .99),
    max: vals.length ? vals[vals.length - 1] : null, sd
  };
}

function fmtMsCell(v) {
  return v === null ? '—' : (v < 100 ? (Math.round(v * 10) / 10) + '' : Math.round(v) + '');
}

// 阈值配色：超过 warn 橙色，超过 bad 红色。阈值来自配置，可按线路基线调。
function thCls(v, warn, bad) {
  if (v === null || !isFinite(v)) return '';
  if (bad > 0 && v >= bad) return ' lm-bad';
  if (warn > 0 && v >= warn) return ' lm-warn';
  return '';
}

function statRowsFor(tabKey) {
  if (tabKey === 'wan1') return V4_TARGETS.map(t => ({ label:t, keys: EXIT1_KEY + '|' + t }));
  if (tabKey === 'wan2') return V4_TARGETS.map(t => ({ label:t, keys: EXIT2_KEY + '|' + t }));
  if (tabKey === 'v6') {
    const rows = [];
    V6_TARGETS.forEach(t => {
      rows.push({ label: labelOf(EXIT1_KEY) + 'v6 · ' + t, keys: V61_KEY + '|' + t });
      rows.push({ label: labelOf(EXIT2_KEY) + 'v6 · ' + t, keys: V62_KEY + '|' + t });
    });
    return rows;
  }
  // overview：每条线路 × 每个目标，一整张表
  const l1 = labelOf(EXIT1_KEY), l2 = labelOf(EXIT2_KEY);
  const rows = [];
  V4_TARGETS.forEach(t => rows.push({ group: l1, label: t, keys: EXIT1_KEY + '|' + t }));
  V4_TARGETS.forEach(t => rows.push({ group: l2, label: t, keys: EXIT2_KEY + '|' + t }));
  V6_TARGETS.forEach(t => rows.push({ group: l1 + '·v6', label: t, keys: V61_KEY + '|' + t }));
  V6_TARGETS.forEach(t => rows.push({ group: l2 + '·v6', label: t, keys: V62_KEY + '|' + t }));
  return rows;
}

function statCells(r) {
  const s = statFor(r.keys);
  // 丢包率配色：<0.05% 算作干净（不标色）；<1% 用橙色提示；>=1% 才是红色告警。
  // 以前一律 loss>0 就标红，会把四舍五入后显示成 0.0% 的极小值也烧成红色，自相矛盾。
  const lossTxt = s.loss === null ? '—'
    : (s.loss < 0.05 ? '0%'
      : (s.loss < 1 ? s.loss.toFixed(1) : Math.round(s.loss)) + '%');
  const lossCls = (s.loss === null || s.loss < 0.05) ? ''
    : (s.loss < 1 ? ' lm-warn' : ' lm-bad');
  return '<td class="ant-table-cell">' + r.label + '</td>'
    + '<td class="ant-table-cell lm-num">' + s.ok + ' / ' + s.records + '</td>'
    + '<td class="ant-table-cell lm-num' + lossCls + '">' + lossTxt + '</td>'
    + '<td class="ant-table-cell lm-num">' + fmtMsCell(s.avg) + '</td>'
    + '<td class="ant-table-cell lm-num">' + fmtMsCell(s.p50) + '</td>'
    + '<td class="ant-table-cell lm-num">' + fmtMsCell(s.p95) + '</td>'
    + '<td class="ant-table-cell lm-num">' + fmtMsCell(s.p99) + '</td>'
    + '<td class="ant-table-cell lm-num' + thCls(s.max, TH_MAX_WARN, TH_MAX_BAD) + '">' + fmtMsCell(s.max) + '</td>'
    + '<td class="ant-table-cell lm-num' + thCls(s.sd,  TH_SD_WARN,  TH_SD_BAD)  + '">' + fmtMsCell(s.sd) + '</td>';
}

const STAT_TABS = ['overview', 'wan1', 'wan2', 'v6'];
function renderStats() {
  STAT_TABS.forEach(tabKey => {
    const box = document.getElementById('statBox-' + tabKey);
    if (!box) return;
    const rows = statRowsFor(tabKey);
    const showGroup = tabKey === 'overview';

    // 连续相同 group 的行合并成一格
    let body = '';
    for (let i = 0; i < rows.length; ) {
      const g = rows[i].group;
      let span = 1;
      while (i + span < rows.length && rows[i + span].group === g) span++;
      for (let j = 0; j < span; j++) {
        body += '<tr class="ant-table-row ant-table-row-level-0">'
          + (showGroup && j === 0 ? '<td class="ant-table-cell lm-group" rowspan="' + span + '">' + g + '</td>' : '')
          + statCells(rows[i + j])
          + '</tr>';
      }
      i += span;
    }

    const wins = STAT_WINDOWS.map(w =>
      '<label class="ant-segmented-item' + (w.k === statWin ? ' ant-segmented-item-selected' : '') + '" data-w="' + w.k + '">' +
        '<input type="radio" class="ant-segmented-item-input"' + (w.k === statWin ? ' checked' : '') + '>' +
        '<div class="ant-segmented-item-label">' + w.label + '</div>' +
      '</label>').join('');

    box.className = 'ant-card lm-panel';
    box.innerHTML =
      '<div class="ant-card-head"><div class="ant-card-head-wrapper">'
      + '<div class="ant-card-head-title">统计 · 每个监测目标</div>'
      + '<div class="ant-card-extra"><div class="ant-segmented"><div class="ant-segmented-group">' + wins + '</div></div></div>'
      + '</div></div>'
      + '<div class="ant-card-body">'
      +   '<div class="ant-table"><div class="ant-table-container"><div class="ant-table-content">'
      +     '<table style="table-layout:auto"><thead class="ant-table-thead"><tr class="ant-table-row">'
      +       (showGroup ? '<th class="ant-table-cell">线路</th>' : '')
      +       '<th class="ant-table-cell">目标</th><th class="ant-table-cell">样本(有效/总)</th>'
      +       '<th class="ant-table-cell">丢包率</th><th class="ant-table-cell">平均</th>'
      +       '<th class="ant-table-cell">p50</th><th class="ant-table-cell">p95</th>'
      +       '<th class="ant-table-cell">p99</th><th class="ant-table-cell">最大</th>'
      +       '<th class="ant-table-cell">波动σ</th>'
      +     '</tr></thead><tbody class="ant-table-tbody">' + body + '</tbody></table>'
      +   '</div></div></div>'
      +   '<div class="lm-stat-note">「样本」是窗口内的成功次数 / 总采集次数。丢包率取每次采集的丢包百分比的平均；'
      +   '平均与分位数只统计成功样本，波动σ 是它们的标准差。'
      +   'ICMP 类目标若被运营商限制会显示成高丢包，那是限制不是线路故障。</div>'
      + '</div>';
  });
  syncStatWinButtons();
}

// 统计时间窗切换（事件委托：表格每次重建，按钮不单独绑事件）
document.addEventListener('click', e => {
  const b = e.target.closest && e.target.closest('.ant-segmented-item[data-w]');
  if (b) setStatWin(b.dataset.w);
});

// ==================== 总览 ====================
// 数值配色跟 antd 的语义色走：<60ms 成功色、<120ms 警告色、其余错误色
function valColor(a) {
  if (a === null) return C_ERROR;
  if (a < 60) return C_SUCCESS;
  if (a < 120) return C_WARNING;
  return C_ERROR;
}
function renderOverview() {
  const cards = [];
  [[labelOf(EXIT1_KEY) + '平均延迟', EXIT1_KEY], [labelOf(EXIT2_KEY) + '平均延迟', EXIT2_KEY]].forEach(([label, key]) => {
    const vals = V4_TARGETS.map(t => lastValue(key + '|' + t)).filter(v => v !== null);
    const a = avg(vals);
    const hasFail = V4_TARGETS.some(t => {
      const s = histData[histData.length-1]?.series[key + '|' + t];
      return s && (s.value === null || Number(s.status) > 0);
    });
    cards.push({
      label, value: a !== null ? Math.round(a) + 'ms' : '—',
      color: valColor(a),
      detail: hasFail ? '最近一次存在丢包/失败目标' : '全部目标正常'
    });
  });
  const v6a = V6_TARGETS.some(t => lastValue(V61_KEY + '|' + t) !== null);
  const v6b = V6_TARGETS.some(t => lastValue(V62_KEY + '|' + t) !== null);
  const v6detail = V6_TARGETS.join('/');
  cards.push({ label:'IPv6 ' + labelOf(EXIT1_KEY), value: v6a ? '可达' : '不可达', color: v6a ? C_SUCCESS : C_ERROR, detail: v6detail });
  cards.push({ label:'IPv6 ' + labelOf(EXIT2_KEY), value: v6b ? '可达' : '不可达', color: v6b ? C_SUCCESS : C_ERROR, detail: v6detail });
  cards.push({ label:'采集点数', value: histData.length + '', color:'', detail: histData.length ? fmtFull(histData[0].ts) + ' ~ ' + fmtFull(histData[histData.length-1].ts) : '暂无数据' });

  document.getElementById('overviewCards').innerHTML = cards.map(c =>
    '<div class="ant-card"><div class="ant-card-body">'
    + '<div class="ant-statistic">'
    +   '<div class="ant-statistic-title">' + c.label + '</div>'
    +   '<div class="ant-statistic-content"' + (c.color ? ' style="color:' + c.color + '"' : '') + '>'
    +     '<span class="ant-statistic-content-value">' + c.value + '</span>'
    +   '</div>'
    + '</div>'
    + '<div class="lm-detail">' + c.detail + '</div>'
    + '</div></div>'
  ).join('');

  renderSparks();

  const labels = V4_TARGETS;
  const w1 = labels.map(t => lastValue(EXIT1_KEY + '|' + t) ?? 0);
  const w2 = labels.map(t => lastValue(EXIT2_KEY + '|' + t) ?? 0);
  if (charts.barChart) charts.barChart.destroy();
  charts.barChart = new Chart(document.getElementById('barChart'), {
    type: 'bar',
    data: {
      labels,
      datasets: [
        { label: labelOf(EXIT1_KEY), data:w1, backgroundColor:'rgba(23,125,220,.8)' },
        { label: labelOf(EXIT2_KEY), data:w2, backgroundColor:'rgba(73,170,25,.8)' }
      ]
    },
    options: {
      responsive:true, maintainAspectRatio:false, animation:false,
      plugins:{ legend:{ labels:{ color:C_TEXT_2, boxWidth:12 } } },
      scales:{
        x:{ ticks:{color:C_TEXT_2}, grid:{color:C_GRID} },
        y:{ beginAtZero:true, ticks:{color:C_TEXT_2}, grid:{color:C_GRID},
            title:{display:true,text:'ms',color:C_TEXT_2} }
      }
    }
  });
}

const sparkCharts = [];
function renderSparks() {
  const grid = document.getElementById('sparkGrid');
  grid.innerHTML = '';
  sparkCharts.forEach(c => c.destroy());
  sparkCharts.length = 0;

  const l1 = labelOf(EXIT1_KEY), l2 = labelOf(EXIT2_KEY);
  const defs = [
    { title:l1 + ' → 各目标', tab:'wan1', keys: V4_TARGETS.map(t => ({ label:t, key: EXIT1_KEY+'|'+t })) },
    { title:l2 + ' → 各目标', tab:'wan2', keys: V4_TARGETS.map(t => ({ label:t, key: EXIT2_KEY+'|'+t })) },
    { title:l1 + 'v6 → v6 DNS', tab:'ipv6', keys: V6_TARGETS.map(t => ({ label:t, key: V61_KEY+'|'+t })) },
    { title:l2 + 'v6 → v6 DNS', tab:'ipv6', keys: V6_TARGETS.map(t => ({ label:t, key: V62_KEY+'|'+t })) }
  ];

  defs.forEach(def => {
    const card = document.createElement('div');
    card.className = 'ant-card lm-spark';
    card.innerHTML =
      '<div class="ant-card-body">'
      + '<div class="lm-spark-head"><span class="lm-spark-title">' + def.title + '</span>'
      + '<span class="lm-spark-avg"></span></div>'
      + '<div class="lm-spark-canvas"><canvas></canvas></div>'
      + '</div>';
    card.addEventListener('click', () => switchTab(def.tab));
    grid.appendChild(card);

    const datasets = def.keys.map((k, i) => ({
      label: k.label,
      data: histData.map(d => {
        const s = d.series[k.key];
        return (s && s.value !== null) ? { x: d.ts*1000, y: s.value } : null;
      }).filter(Boolean),
      borderColor: PALETTE[i % PALETTE.length],
      borderWidth: 1.2, pointRadius: 0,
      tension: smoothOn ? 0.4 : 0,
      cubicInterpolationMode: smoothOn ? 'monotone' : 'default',
      spanGaps: false
    }));
    const all = datasets.flatMap(ds => ds.data.map(p => p.y));
    const a = avg(all);
    card.querySelector('.lm-spark-avg').textContent = a !== null ? 'avg ' + Math.round(a) + 'ms' : '';

    sparkCharts.push(new Chart(card.querySelector('canvas'), {
      type: 'line',
      data: { datasets },
      options: {
        responsive:true, maintainAspectRatio:false, animation:false,
        plugins:{ legend:{display:false}, tooltip:{enabled:false} },
        scales:{ x:{ type:'time', display:false }, y:{ display:false, beginAtZero:true } }
      }
    }));
  });
}

// ==================== TCP 流 ====================
function renderTcp() {
  const tbody = document.getElementById('tcpBody');
  const fSvc = document.getElementById('fService');
  const fIf  = document.getElementById('fIface').value;
  const fCl  = document.getElementById('fClient').value.trim();

  const svcs = [...new Set(tcpData.streams.map(s => s.service))].sort();
  const cur = fSvc.value;
  fSvc.innerHTML = '<option value="">全部服务</option>' + svcs.map(s => '<option' + (s===cur?' selected':'') + '>' + s + '</option>').join('');

  let synCount = 0;
  tcpData.streams.forEach(s => { if (s.state === 'SYN_SENT') synCount++; });
  document.getElementById('synCount').textContent = synCount;

  const rows = tcpData.streams.filter(s => {
    if (cur && s.service !== cur) return false;
    if (fIf && labelOf(s.iface) !== fIf) return false;
    if (fCl && !s.client.includes(fCl)) return false;
    return true;
  });
  tbody.innerHTML = rows.map(s => {
    const tc = tagClassOf(s.iface);
    return '<tr class="ant-table-row ant-table-row-level-0' + (s.state === 'SYN_SENT' ? ' lm-row-syn' : '') + '">'
      + '<td class="ant-table-cell">' + s.client + '</td>'
      + '<td class="ant-table-cell">' + s.sport + '</td>'
      + '<td class="ant-table-cell">' + s.dst + '</td>'
      + '<td class="ant-table-cell">' + s.dport + '</td>'
      + '<td class="ant-table-cell"><span class="ant-tag ' + tc + '">' + labelOf(s.iface) + '</span></td>'
      + '<td class="ant-table-cell">' + s.service + '</td>'
      + '<td class="ant-table-cell">' + s.state + '</td></tr>';
  }).join('') || '<tr class="ant-table-row"><td class="ant-table-cell lm-empty" colspan="7">暂无活跃 TCP 连接</td></tr>';

  document.getElementById('tcpTime').textContent = tcpData.ts ? '采集于 ' + fmtFull(tcpData.ts) : '';
}

// ==================== 数据加载 ====================
let histErr = 0;
async function loadHist() {
  try {
    const r = await fetch(HIST_URL + '?t=' + Date.now(), { cache: 'no-store' });
    if (!r.ok) throw new Error('HTTP ' + r.status);
    const text = await r.text();
    histData = parseHistory(text);
    histErr = 0;
    document.getElementById('lastUpdate').textContent =
      '延迟更新 ' + new Date().toLocaleTimeString() + '（' + histData.length + ' 点）';
    renderOverview();
    ['wan1','wan2','v6'].forEach(k => {
      const st = chartState[k];
      if (!st) return;
      if (!st.isLive && st.sliderIdx > histData.length - 1) {
        st.sliderIdx = Math.max(0, histData.length - 1);
      }
      if (st.isLive) st.sliderIdx = Math.max(0, histData.length - 1);
      st.syncTimeline();
      drawChart(k);
      refreshToggleValues(k);
    });
    renderStats();
  } catch (e) {
    histErr++;
    if (histErr === 1) console.warn('history.log 加载失败:', e.message);
    document.getElementById('lastUpdate').textContent = '延迟数据加载失败（' + e.message + '）';
  }
}
async function loadTcp() {
  try {
    const r = await fetch(TCP_URL + '?t=' + Date.now(), { cache: 'no-store' });
    if (!r.ok) throw new Error('HTTP ' + r.status);
    tcpData = await r.json();
    renderTcp();
  } catch (e) { console.warn('tcp.json 加载失败:', e.message); }
}

// ==================== 标签切换 ====================
function switchTab(name) {
  document.querySelectorAll('#mainTabs .ant-tabs-tab').forEach(t => {
    const on = t.dataset.tab === name;
    t.classList.toggle('ant-tabs-tab-active', on);
    const btn = t.querySelector('.ant-tabs-tab-btn');
    if (btn) btn.setAttribute('aria-selected', on ? 'true' : 'false');
  });
  document.querySelectorAll('.lm-pane').forEach(t => t.classList.toggle('active', t.id === 'tab-' + name));
  // 切回的图表需要重算尺寸
  const map = { wan1:'wan1', wan2:'wan2', ipv6:'v6' };
  if (map[name] && charts[map[name]]) setTimeout(() => charts[map[name]].resize(), 0);
  if (name === 'overview') setTimeout(() => { charts.barChart?.resize(); sparkCharts.forEach(c => c.resize()); }, 0);
}
document.querySelectorAll('#mainTabs .ant-tabs-tab').forEach(tab => {
  tab.addEventListener('click', () => switchTab(tab.dataset.tab));
});
['fService','fIface','fClient'].forEach(id => document.getElementById(id).addEventListener('input', renderTcp));

// ==================== 启动 ====================
// 必须先拿到 config.json 再建图：曲线名字、出口名都来自配置
(async function boot() {
  await loadConfig();

  smoothOn = loadSmooth();
  syncSmoothButtons();
  ['wan1','wan2','v6'].forEach(k => {
    document.getElementById('smoothBtn-' + k).addEventListener('click', () => setSmooth(!smoothOn));
  });
  initLineTab('wan1', 'chartWan1');
  initLineTab('wan2', 'chartWan2');
  initLineTab('v6', 'chartV6');
  loadStatWin();
  renderStats();
  loadHist();
  loadTcp();
  setInterval(loadHist, HIST_REFRESH);
  setInterval(loadTcp, TCP_REFRESH);
})();
