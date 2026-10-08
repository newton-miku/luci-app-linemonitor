#!/bin/sh
# 统一历史日志里的目标名，并当场重跑一次采集验证
# 背景：douyin.com 这个目标曾在配置里叫过「字节」，历史日志因此混有两套名字，
#      看板统计表按「线路×目标名」分组，会把同一个目标拆成两行。
LOG=/www/lm/history.log

echo "=== 改名前 ==="
tr ' ' '\n' < "$LOG" | grep -c '字节='

cp "$LOG" "$LOG.bak-rename"
sed -i 's/字节=/抖音=/g' "$LOG"

echo "=== 改名后 ==="
tr ' ' '\n' < "$LOG" | grep -c '字节='
echo "--- wan 目标名分布 ---"
tr ' ' '\n' < "$LOG" | grep '^wan|' | cut -d'=' -f1 | sort | uniq -c | sort -rn

echo
echo "=== 跑一次采集（看 auto 源地址是否生效）==="
sh /usr/bin/line_monitor.sh
tail -n 1 "$LOG" | tr ' ' '\n' | grep '^wan|'
echo "--- 残留的 3000 优先级策略路由（应为空）---"
ip rule | grep 3000
