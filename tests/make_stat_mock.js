// make_stat_mock.js — 生成用于验证统计功能的 mock history.log
// 关键点：eth1|阿里DNS 的值就是序号 0..149，便于手算核对分位数
const fs = require('fs');
const path = require('path');

const N = 150;                       // 150 个采集点 = 150 分钟
const STEP = 60;                     // 60 秒一个点
const now = Math.floor(Date.now() / 1000);
const base = now - (N - 1) * STEP;

const V4 = ['阿里DNS', '腾讯DNS', 'CNNIC', '微信', '淘宝', 'B站', '字节', 'QQ'];
const V6 = ['阿里v6', '腾讯v6', '移动v6'];
const EXITS = ['eth1', 'pppoe-wan2'];

const lines = [];
for (let i = 0; i < N; i++) {
  const ts = base + i * STEP;
  const parts = [String(ts)];

  EXITS.forEach(ex => {
    V4.forEach(t => {
      let v, loss = 0;
      if (ex === 'eth1' && t === '阿里DNS') {
        v = i;                                   // 0..149，精确可算
      } else if (ex === 'pppoe-wan2' && t === '阿里DNS') {
        v = 100;                                 // 恒定值，σ 应为 0
      } else if (ex === 'eth1' && t === 'CNNIC') {
        // 每 10 个点失败一次 → 丢包率 10%
        if (i % 10 === 0) { v = null; loss = 100; }
        else v = 30;
      } else {
        v = 20 + ((i * 7 + t.length * 13) % 40);  // 伪随机 20..59
      }
      parts.push(ex + '|' + t + '=' + (v === null ? 'FAIL' : v) + ',' + loss);
    });
  });

  EXITS.forEach(ex => {
    V6.forEach(t => {
      // 移动 v6 全失败（模拟真实情况：无可用 v6 源地址）
      const fail = (ex === 'eth1');
      const v = fail ? null : 40 + ((i * 3) % 20);
      parts.push('v6-' + ex + '|' + t + '=' + (v === null ? 'FAIL' : v) + ',' + (fail ? 100 : 0));
    });
  });

  lines.push(parts.join(' '));
}

const outDir = path.join(__dirname, 'statmock');
fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, 'history.log'), lines.join('\n') + '\n');
fs.writeFileSync(path.join(outDir, 'tcp.json'), JSON.stringify({ ts: now, streams: [] }));

console.log('点数 =', N);
console.log('时间范围 =', new Date(base * 1000).toLocaleString(), '~', new Date(now * 1000).toLocaleString());
console.log('eth1|阿里DNS 全部      : n=' + N + ' 均值=' + (0 + N - 1) / 2 + ' p95=' + ((N - 1) * 0.95) + ' p99=' + ((N - 1) * 0.99));
console.log('eth1|阿里DNS 最近 60 点: 均值=' + (90 + 149) / 2 + ' p95=' + (90 + 59 * 0.95) + ' p99=' + (90 + 59 * 0.99));
