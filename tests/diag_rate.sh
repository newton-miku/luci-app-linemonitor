#!/bin/sh
# diag_rate.sh — 排查实时速率显示不正确
echo "=== targets.conf 速率相关 ==="
grep -n 'RATE_IFACES\|INTERVAL_RATE\|^EXITS=' /etc/line-monitor/targets.conf
echo
echo "=== /tmp/lm_rate.json ==="
cat /tmp/lm_rate.json 2>/dev/null || echo "(无)"
echo
echo "=== /tmp/lm_rate.state ==="
cat /tmp/lm_rate.state 2>/dev/null || echo "(无)"
echo
echo "=== /proc/net/dev 关心接口 ==="
grep -E 'wan|pppoe-wan|br-lan|eth0|组网客户端' /proc/net/dev
echo
echo "=== 进程 ==="
ps w | grep -E '[l]m_rate|[l]ine_daemon|[l]ine_monitor'
echo
echo "=== line_daemon.sh ==="
cat /usr/bin/line_daemon.sh 2>/dev/null
echo
echo "=== crontab ==="
crontab -l 2>/dev/null
echo
echo "=== date ==="
date
