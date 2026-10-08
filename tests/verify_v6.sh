#!/bin/sh
# 用修好的采集脚本跑一轮，看 v6 是否还全 FAIL
set -e
sh -n /usr/bin/line_monitor.sh && echo "SHELL_SYNTAX_OK"

echo
echo "===== v6_src_of 探测结果 ====="
for i in wan pppoe-wan; do
    s=$(ip -6 addr show dev "$i" scope global 2>/dev/null |
        awk '/inet6 /{sub(/\/.*/,"",$2); if ($2 !~ /^f[cd]/) { print $2; exit }}')
    printf '%-14s -> %s\n' "$i" "${s:-（取不到）}"
done

echo
echo "===== 各 v6 目标逐接口实测 ====="
for i in wan pppoe-wan; do
    s=$(ip -6 addr show dev "$i" scope global 2>/dev/null |
        awk '/inet6 /{sub(/\/.*/,"",$2); if ($2 !~ /^f[cd]/) { print $2; exit }}')
    for t in 2400:3200::1 2402:4e00:: 2409:8080::8; do
        out=$(ping6 -I "$s" -c 3 -W 2 "$t" 2>&1 | tail -2 | tr '\n' ' ')
        printf '%-14s %-16s -> %s\n' "$i" "$t" "$out"
    done
done

echo
echo "===== 采集日志最后 3 行的 v6 字段（改造前）====="
tail -3 /www/lm/history.log | while read -r line; do
    echo "$line" | tr ' ' '\n' | grep '^v6-' | tr '\n' ' '
    echo
done

echo
echo "===== 手动跑一轮采集，看新写入的行 ====="
BEFORE=$(wc -l < /www/lm/history.log)
/usr/bin/line_monitor.sh
AFTER=$(wc -l < /www/lm/history.log)
echo "行数 $BEFORE -> $AFTER"
echo "新行："
tail -1 /www/lm/history.log | tr ' ' '\n' | grep '^v6-' | tr '\n' ' '
echo
