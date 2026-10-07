#!/bin/sh
echo "=== 停守护进程，避免互相干扰 ==="
/etc/init.d/linemon stop 2>/dev/null
sleep 1
rm -f /tmp/lm_rate.state /tmp/lm_rate_ct.state
echo
echo "=== 第 1 次（建基线） ==="
S=$(date +%s%N 2>/dev/null || date +%s)
/usr/bin/lm_rate.sh
E=$(date +%s%N 2>/dev/null || date +%s)
cat /tmp/lm_rate.json
echo "state 文件: $(ls -l /tmp/lm_rate.state 2>&1)"
echo "ct state 行数: $(wc -l < /tmp/lm_rate_ct.state 2>&1)"
echo
echo "=== 分段耗时（用 /usr/bin/time 或直接跑内层） ==="
awk 'BEGIN{}' 
time awk -v marks="256 512 768" 'END{}' /proc/net/nf_conntrack
time uci -q get network.lan.ipaddr
time cat /proc/net/dev
echo
echo "=== sleep 4 后第 2 次 ==="
sleep 4
time /usr/bin/lm_rate.sh
cat /tmp/lm_rate.json
echo
echo "=== 状态文件 ==="
cat /tmp/lm_rate.state
echo
echo "=== 起回守护进程 ==="
/etc/init.d/linemon start
sleep 5
cat /tmp/lm_rate.json