
const CGI = '/cgi-bin/lm-config';
const $ = id => document.getElementById(id);
let statusTimer = null;

function setStatus(msg, cls) {
  const el = $('status');
  el.textContent = msg;
  el.className = 'lm-status ' + (cls || '');
  if (statusTimer) clearTimeout(statusTimer);
  if (msg) statusTimer = setTimeout(() => { el.textContent = ''; }, 6000);
}

// ---------- 读配置 ----------
async function loadConf() {
  setStatus('读取中…');
  try {
    const r = await fetch(CGI + '?t=' + Date.now(), { cache: 'no-store' });
    if (!r.ok) throw new Error('HTTP ' + r.status);
    const txt = await r.text();
    fillForm(txt);
    setStatus('已加载', 'lm-ok');
  } catch (e) {
    setStatus('读取失败：' + e.message, 'lm-bad');
  }
}

function grab(txt, name, dflt) {
  const m = txt.match(new RegExp('^' + name + '=(.*)$', 'm'));
  if (!m) return dflt;
  let v = m[1].trim();
  if (v.startsWith('"') && v.endsWith('"')) v = v.slice(1, -1);
  return v;
}
function grabExits(txt) {
  const m = txt.match(/EXITS="([\s\S]*?)"/);
  if (!m) return [];
  return m[1].split(/\s+/).filter(Boolean).map(line => {
    const p = line.split('|');
    return { iface: p[0] || '', label: p[1] || '', src: p[2] || '', mark: p[3] || '' };
  });
}
// "名字:地址 名字:地址" -> 每行一条
function grabTargets(txt, name) {
  return grab(txt, name, '').split(/\s+/).filter(Boolean).join('\n');
}

function fillForm(txt) {
  $('dashTitle').value    = grab(txt, 'DASH_TITLE', '线路质量监测看板');
  $('dashSubtitle').value = grab(txt, 'DASH_SUBTITLE', '');
  $('lanPrefix').value    = grab(txt, 'LAN_PREFIX', '192.168.66.');
  $('icmpTargets').value  = grabTargets(txt, 'ICMP_TARGETS');
  $('httpTargets').value  = grabTargets(txt, 'HTTP_TARGETS');
  $('icmp6Targets').value = grabTargets(txt, 'ICMP6_TARGETS');
  $('pingCount').value       = grab(txt, 'PING_COUNT', '3');
  $('curlTimeout').value     = grab(txt, 'CURL_TIMEOUT', '4');
  $('keepLines').value       = grab(txt, 'KEEP_LINES', '1440');
  $('publicDns').value       = grab(txt, 'PUBLIC_DNS', '223.5.5.5');
  $('intervalMonitor').value = grab(txt, 'INTERVAL_MONITOR', '60');
  $('intervalTcp').value     = grab(txt, 'INTERVAL_TCP', '5');
  $('statMaxWarn').value     = grab(txt, 'STAT_MAX_WARN', '300');
  $('statMaxBad').value      = grab(txt, 'STAT_MAX_BAD', '1000');
  $('statSdWarn').value      = grab(txt, 'STAT_SD_WARN', '50');
  $('statSdBad').value       = grab(txt, 'STAT_SD_BAD', '200');

  const exits = grabExits(txt);
  $('exitRows').innerHTML = '';
  (exits.length ? exits : [{ iface:'', label:'', src:'', mark:'' }]).forEach(addExitRow);
  renderPreview();
}

// ---------- 出口行 ----------
function addExitRow(e) {
  e = e || { iface:'', label:'', src:'', mark:'' };
  const tr = document.createElement('tr');
  tr.className = 'ant-table-row ant-table-row-level-0';
  tr.innerHTML =
    '<td class="ant-table-cell"><input class="ant-input e-if" type="text" placeholder="eth1"></td>' +
    '<td class="ant-table-cell"><input class="ant-input e-label" type="text" placeholder="移动"></td>' +
    '<td class="ant-table-cell"><input class="ant-input e-src" type="text" placeholder="可留空"></td>' +
    '<td class="ant-table-cell"><input class="ant-input e-mark" type="text" placeholder="256"></td>' +
    '<td class="ant-table-cell"><button class="ant-btn ant-btn-sm ant-btn-dangerous" type="button"><span>删除</span></button></td>';
  tr.querySelector('.e-if').value = e.iface;
  tr.querySelector('.e-label').value = e.label;
  tr.querySelector('.e-src').value = e.src;
  tr.querySelector('.e-mark').value = e.mark;
  tr.querySelector('button').addEventListener('click', () => { tr.remove(); renderPreview(); });
  tr.querySelectorAll('input').forEach(i => i.addEventListener('input', renderPreview));
  $('exitRows').appendChild(tr);
}
function readExits() {
  return [...$('exitRows').querySelectorAll('tr')].map(tr => ({
    iface: tr.querySelector('.e-if').value.trim(),
    label: tr.querySelector('.e-label').value.trim(),
    src:   tr.querySelector('.e-src').value.trim(),
    mark:  tr.querySelector('.e-mark').value.trim()
  })).filter(e => e.iface);
}

// ---------- 生成配置文本 ----------
function buildConf() {
  const exits = readExits();
  const exitLines = exits.map(e => [e.iface, e.label, e.src, e.mark].join('|')).join('\n');
  const oneLine = s => s.split('\n').map(x => x.trim()).filter(Boolean).join(' ');

  return [
    '# ============================================================',
    '# 线路监测配置',
    '# 这个文件由设置页 http://192.168.66.1/lm/config.html 生成，',
    '# 也可以直接用 vi 改 —— 采集脚本每轮都会重新读取，保存即生效。',
    '# ============================================================',
    '',
    '# ---------------- 看板 ----------------',
    'DASH_TITLE="' + $('dashTitle').value.trim() + '"',
    'DASH_SUBTITLE="' + $('dashSubtitle').value.trim() + '"',
    '',
    '# ---------------- 出口定义 ----------------',
    '# 每行一个出口，格式：接口名|显示名|源IP|mark值',
    '#   接口名  路由器上的网络接口，用于 ping -I / curl --interface',
    '#   显示名  看板上显示的名字，不能有空格',
    '#   源IP    测 HTTP 目标需要源地址策略路由时填，不需要就留空',
    '#   mark    该出口在 conntrack 里的 fwmark，多个用逗号分隔',
    'EXITS="',
    exitLines,
    '"',
    '',
    '# ---------------- 内网 ----------------',
    'LAN_PREFIX="' + $('lanPrefix').value.trim() + '"',
    '',
    '# ---------------- 监测目标 ----------------',
    'ICMP_TARGETS="' + oneLine($('icmpTargets').value) + '"',
    'HTTP_TARGETS="' + oneLine($('httpTargets').value) + '"',
    'ICMP6_TARGETS="' + oneLine($('icmp6Targets').value) + '"',
    '',
    '# ---------------- 采集参数 ----------------',
    'PING_COUNT=' + ($('pingCount').value.trim() || '3'),
    'CURL_TIMEOUT=' + ($('curlTimeout').value.trim() || '4'),
    'KEEP_LINES=' + ($('keepLines').value.trim() || '1440'),
    'PUBLIC_DNS=' + ($('publicDns').value.trim() || '223.5.5.5'),
    'INTERVAL_MONITOR=' + ($('intervalMonitor').value.trim() || '60'),
    'INTERVAL_TCP=' + ($('intervalTcp').value.trim() || '5'),
    '',
    '# ---------------- 看板统计表配色阈值 ----------------',
    'STAT_MAX_WARN=' + ($('statMaxWarn').value.trim() || '300'),
    'STAT_MAX_BAD=' + ($('statMaxBad').value.trim() || '1000'),
    'STAT_SD_WARN=' + ($('statSdWarn').value.trim() || '50'),
    'STAT_SD_BAD=' + ($('statSdBad').value.trim() || '200'),
    ''
  ].join('\n');
}
function renderPreview() { $('preview').textContent = buildConf(); }

// ---------- 保存 ----------
async function saveConf() {
  const text = buildConf();
  setStatus('保存中…');
  try {
    const r = await fetch(CGI, {
      method: 'POST',
      headers: { 'Content-Type': 'text/plain; charset=utf-8' },
      body: text
    });
    const j = await r.json();
    if (!j.ok) throw new Error(j.error || '未知错误');
    setStatus('已保存，' + j.bytes + ' 字节。看板刷新后生效（延迟曲线最多等一个采集周期）。', 'lm-ok');
  } catch (e) {
    setStatus('保存失败：' + e.message, 'lm-bad');
  }
}

// ---------- 绑定 ----------
document.querySelectorAll('input, textarea').forEach(el => el.addEventListener('input', renderPreview));
$('addExit').addEventListener('click', () => { addExitRow(); renderPreview(); });
$('saveBtn').addEventListener('click', saveConf);
$('reloadBtn').addEventListener('click', loadConf);

loadConf();
