#!/bin/sh
# verify_rate4.sh — 隔离验证：停守护，手工跑两次，看 ts 变没变 + 计时
/etc/init.d/linemon stop 2>/dev/null
sleep 1
rm -f /tmp/lm_rate.state /tmp/lm_rate_ct.state
echo "=== 第 1 次 ==="
/usr/bin/lm_rate.sh
cat /tmp/lm_rate.json; echo
echo "state: [$(cat /tmp/lm_rate.state 2>&1 | tr '\n' ';')]"
echo "ct 行数: $(wc -l < /tmp/lm_rate_ct.state 2>&1)"
echo
echo "=== 睡 5 秒，第 2 次（计时） ==="
sleep 5
T0=$(date +%s)
/usr/bin/lm_rate.sh
T1=$(date +%s)
echo "耗时 $((T1-T0))s"
cat /tmp/lm_rate.json; echo
echo
echo "=== 睡 5 秒，第 3 次 ==="
sleep 5
/usr/bin/lm_rate.sh
cat /tmp/lm_rate.json; echo
echo
echo "=== 起回守护，等 10 秒看是否持续刷新 ==="
/etc/init.d/linemon start
sleep 10
cat /tmp/lm_rate.json; echo
echo "现在时刻: $(date +%s)"
echo "残留临时目录: $(ls -d /tmp/lm_rate.[0-9]* 2>/dev/null | wc -l)"