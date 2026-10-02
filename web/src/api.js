// 数据层：全是从路由器上直接取的静态文件，没有后端接口。
// history.log / config.json / tcp.json 都在看板同级的上一层（/lm/ 下）。

const BASE = '../';

async function fetchText(name) {
  const r = await fetch(BASE + name, { cache: 'no-store' });
  if (!r.ok) throw new Error(name + ' HTTP ' + r.status);
  return r.text();
}

async function fetchJson(name, dflt) {
  try {
    const r = await fetch(BASE + name, { cache: 'no-store' });
    if (!r.ok) throw new Error('HTTP ' + r.status);
    return await r.json();
  } catch (e) {
    return dflt;
  }
}

// 一行形如：
//   1790908984 eth1|阿里DNS=39.818,0 eth1|... v6-pppoe-wan2|国际v6=185.273,0
// 首个字段是秒级时间戳，其后每个 token 是 <键>=<值>,<状态>。
// 值为 FAIL 或「值 0 且状态 1」都算失败（后者是早期 curl 不填 -w 时留下的脏数据）。
export function parseHistory(text) {
  const out = [];
  for (const raw of text.split('\n')) {
    const line = raw.trim();
    if (!line) continue;
    const sp = line.indexOf(' ');
    if (sp < 0) continue;
    const ts = Number(line.slice(0, sp));
    if (!Number.isFinite(ts) || ts <= 0) continue;
    const series = {};
    for (const tok of line.slice(sp + 1).split(' ')) {
      const eq = tok.indexOf('=');
      if (eq <= 0) continue;
      const key = tok.slice(0, eq);
      const rest = tok.slice(eq + 1);
      const comma = rest.lastIndexOf(',');
      if (comma < 0) continue;
      const rawVal = rest.slice(0, comma);
      const rawLoss = rest.slice(comma + 1);
      const num = rawVal === 'FAIL' ? null : Number(rawVal);
      const fail = rawVal === 'FAIL' || (num === 0 && rawLoss === '1');
      series[key] = {
        value: fail || !Number.isFinite(num) ? null : num,
        loss: fail ? 100 : (Number(rawLoss) || 0),
      };
    }
    out.push({ ts, series });
  }
  out.sort((a, b) => a.ts - b.ts);
  return out;
}

export async function loadHistory() {
  return parseHistory(await fetchText('history.log'));
}

export async function loadConfig() {
  return fetchJson('config.json', {
    title: '线路质量监测看板',
    subtitle: '',
    exits: [],
    targets_v4: [],
    targets_v6: [],
  });
}

export async function loadTcp() {
  return fetchJson('tcp.json', []);
}

// 实时速率走 CGI（/cgi-bin/lm-rate），不是静态文件，所以用绝对路径。
// 它读的是 /tmp/lm_rate.json，由 lm_rate.sh 每 INTERVAL_RATE 秒刷新一次。
// 路由器刚装好 / 刚重启时文件还不存在，接口会给 {"ts":0,"rates":[]}。
export async function loadRate() {
  try {
    const r = await fetch('/cgi-bin/lm-rate', { cache: 'no-store' });
    if (!r.ok) throw new Error('HTTP ' + r.status);
    const j = await r.json();
    return Array.isArray(j && j.rates) ? j : { ts: 0, rates: [] };
  } catch (e) {
    return { ts: 0, rates: [] };
  }
}

// 数据指纹：只取首末两行的时间戳，比整文件 hash 便宜得多，
// 而且够用——采集是追加写，首末变了内容就一定变了。
export async function historySig() {
  try {
    const r = await fetch(BASE + 'history.log', { cache: 'no-store' });
    if (!r.ok) return '';
    const text = await r.text();
    const lines = text.trimEnd().split('\n');
    if (!lines.length) return '';
    const head = lines[0].split(' ')[0];
    const tail = lines[lines.length - 1].split(' ')[0];
    return head + '-' + tail + '-' + lines.length;
  } catch (e) {
    return '';
  }
}

export const exitType = (e) => (e && (e.type === 'v4' || e.type === 'v6') ? e.type : 'both');
export const wantsV4 = (e) => exitType(e) !== 'v6';
export const wantsV6 = (e) => exitType(e) !== 'v4';
