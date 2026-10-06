#!/bin/sh
echo "=== 手动跑一次采集（移动 v6 现在有源地址了）==="
sh /usr/bin/line_monitor.sh 2>&1 | tail -8
sleep 2

echo
echo "=== history.log 最新一行的 v6 键 ==="
tail -n 1 /www/lm/history.log 2>/dev/null | tr ' ' '\n' | grep -E '^v6-' | sort

echo
echo "=== 移动出口 v4 键 ==="
tail -n 1 /www/lm/history.log 2>/dev/null | tr ' ' '\n' | grep -E '^eth1\|' | sort

echo
echo "=== 告警配置 ==="
grep -E '^ALERT_ENABLE|^ALERT_SCOPE|^ALERT_MAX_MS|^ALERT_DEBOUNCE|^ALERT_COOLDOWN|^ALERT_LOSS_PCT' /etc/line-monitor/targets.conf

echo
echo "=== 告警状态 ==="
/usr/bin/lm_alert.sh --status 2>&1 | head -25

echo
echo "=== 现在的 v6 默认路由 ==="
ip -6 route show default

echo
echo "=== LAN 客户端前缀（确认还是电信）==="
ip -6 addr show dev br-lan | grep 'scope global'
