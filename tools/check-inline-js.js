// check-inline-js.js — 抽出 HTML 里的 <script> 块做语法检查（不执行）
// 用法: node tools/check-inline-js.js deploy/www/lm/line.html ...
// 退出码非 0 表示有块语法错误；CI 直接拿它当门禁。
const fs = require('fs');
const vm = require('vm');

let bad = 0;
for (const file of process.argv.slice(2)) {
  const html = fs.readFileSync(file, 'utf8');
  const blocks = [...html.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g)].map(m => m[1]);
  if (!blocks.length) { console.log('SKIP (无内联 script)  ' + file); continue; }
  blocks.forEach((code, i) => {
    try {
      new vm.Script(code, { filename: file + '#script' + i });
      console.log('OK   ' + file + ' script#' + i + '  ' + code.length + ' 字符');
    } catch (e) {
      bad++;
      console.error('::error file=' + file + '::script#' + i + ': ' + e.message);
    }
  });
}
process.exit(bad ? 1 : 0);
