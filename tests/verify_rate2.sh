#!/bin/sh
# verify_rate2.sh — 同窗口严格对照：看板出口速率合计 vs eth0 实际吞吐
echo "=== 先清基线，让守护进程重建 ==="
rm -f /tmp/lm_rate.state /tmp/lm_rate_ct.state
sleep 8

awk '/^ *(eth0|br-lan|pppoe-wan|wan|BLUE4):/ { n=$1; gsub(/:/,"",n); print n,$2,$10 }' /proc/net/dev > /tmp/v2_a
cat /tmp/lm_rate.json > /tmp/v2_r0
T0=$(date +%s)
sleep 20
awk '/^ *(eth0|br-lan|pppoe-wan|wan|BLUE4):/ { n=$1; gsub(/:/,"",n); print n,$2,$10 }' /proc/net/dev > /tmp/v2_b
cat /tmp/lm_rate.json > /tmp/v2_r1
T1=$(date +%s)
DT=$((T1-T0))
echo "窗口 ${DT}s"
echo
echo "--- 看板输出（末值，bytes/s） ---"
cat /tmp/v2_r1
echo
echo "--- 接口计数增量换算 ---"
awk -v dt="$DT" 'FNR==NR{rx[$1]=$2;tx[$1]=$3;next}
     { printf "%-12s rx=%9.2f KB/s  tx=%9.2f KB/s\n",$1,($2-rx[$1])/dt/1024,($3-tx[$1])/dt/1024 }' /tmp/v2_a /tmp/v2_b
echo
echo "--- conntrack 归因合计 vs eth0 ---"
awk -v dt="$DT" -v line="$(cat /tmp/v2_r1)" '
BEGIN {
    n = split(line, seg, /"if":"/)
    tot_r = 0; tot_t = 0
    for (i = 2; i <= n; i++) {
        split(seg[i], a, "\"")
        r = a[4] + 0
        t = a[5] + 0
        printf "%-12s conntrack rx=%9.2f KB/s  tx=%9.2f KB/s\n", a[1], r/1024, t/1024
        tot_r += r; tot_t += t
    }
    printf "%-12s conntrack rx=%9.2f KB/s  tx=%9.2f KB/s\n", "合计", tot_r/1024, tot_t/1024
}'
echo
echo "--- 临时文件是否残留（应为 0） ---"
ls /tmp/lm_rate_ct.* 2>/dev/null | grep -v '^/tmp/lm_rate_ct.state$' | wc -l
echo
echo "--- lm_rate.sh 耗时 ---"
time /usr/bin/lm_rate.sh