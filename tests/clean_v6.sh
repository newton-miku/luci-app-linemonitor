#!/bin/sh
# 清洗 v6 的假数据：
#   1. v6-*|腾讯v6=…  整段删（目标 2402:4e00:: 从来就不回包，已换成国际v6）
#   2. v6-*|运营商v6=…  整段删（旧目标 2409:8080::8 不回包，已换成 2409:8080:1::1）
#   3. v6-*|阿里v6=FAIL,100  删（这是 ping6 -I <接口名> 报 Permission denied 造成的假失败）
# 留着会永远拖低 1 小时 / 24 小时窗口的可用率，把真实线路问题淹没。
LOG=/www/lm/history.log
BAK=/www/lm/history.log.bak-v6

echo "清洗前："
printf '  总行数        %s\n' "$(wc -l < "$LOG")"
printf '  腾讯v6 出现   %s\n' "$(grep -o '腾讯v6=' "$LOG" | wc -l)"
printf '  运营商v6 出现   %s\n' "$(grep -o '运营商v6=' "$LOG" | wc -l)"
printf '  阿里v6 失败   %s\n' "$(grep -o '阿里v6=FAIL,100' "$LOG" | wc -l)"

cp "$LOG" "$BAK"

awk '{
  out = $1
  for (i = 2; i <= NF; i++) {
    f = $i
    if (f ~ /\|腾讯v6=/) continue
    if (f ~ /\|运营商v6=/) continue
    if (f ~ /\|阿里v6=FAIL,/) continue
    out = out " " f
  }
  print out
}' "$BAK" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"

echo "清洗后："
printf '  总行数        %s\n' "$(wc -l < "$LOG")"
printf '  腾讯v6 出现   %s\n' "$(grep -o '腾讯v6=' "$LOG" | wc -l)"
printf '  运营商v6 出现   %s\n' "$(grep -o '运营商v6=' "$LOG" | wc -l)"
printf '  阿里v6 失败   %s\n' "$(grep -o '阿里v6=FAIL,100' "$LOG" | wc -l)"
printf '  阿里v6 正常   %s\n' "$(grep -o '阿里v6=[0-9]' "$LOG" | wc -l)"
echo
echo "首行字段数 / 末行字段数："
head -1 "$LOG" | wc -w
tail -1 "$LOG" | wc -w
echo
echo "末行样例："
tail -1 "$LOG" | cut -c1-200
echo
echo "备份在 $BAK（$(wc -l < "$BAK") 行）"
