#!/bin/sh
# verify_rate.sh — 部署后的真机验证：看板速率 vs eth0/接口计数
echo "=== 装好的 lm_rate.sh 语法检查 ==="
sh -n /usr/bin/lm_rate.sh && echo "OK 语法通过" || echo "FAIL 语法错误"
echo
echo "=== 清基线，连跑 3 次 ==="
rm -f /tmp/lm_rate.state /tmp/lm_rate_ct.state
i=1
while [ $i -le 3 ]; do
    /usr/bin/lm_rate.sh
    echo "--- 第 $i 次 ---"
    cat /tmp/lm_rate.json
    i=$((i + 1))
    [ $i -le 3 ] && sleep 6
done
echo
echo "=== conntrack 基线（只看前 3 行 + 总行数） ==="
head -4 /tmp/lm_rate_ct.state
wc -l < /tmp/lm_rate_ct.state
echo
echo "=== 同时刻接口计数增量对照（8 秒） ==="
awk '/^ *(eth0|pppoe-wan2|eth1|br-lan):/ { n=$1; gsub(/:/,"",n); print n,$2,$10 }' /proc/net/dev > /tmp/vr_a
cat /tmp/lm_rate.json > /tmp/vr_r0
T0=$(date +%s)
sleep 8
awk '/^ *(eth0|pppoe-wan2|eth1|br-lan):/ { n=$1; gsub(/:/,"",n); print n,$2,$10 }' /proc/net/dev > /tmp/vr_b
/usr/bin/lm_rate.sh
T1=$(date +%s)
DT=$((T1 - T0))
echo "窗口 ${DT}s"
echo "--- 看板输出 ---"
cat /tmp/lm_rate.json
echo "--- 接口计数换算 ---"
awk -v dt="$DT" '
FNR==NR { rx[$1]=$2; tx[$1]=$3; next }
{ printf "%-12s rx=%9.2f KB/s  tx=%9.2f KB/s\n", $1, ($2-rx[$1])/dt/1024, ($3-tx[$1])/dt/1024 }
' /tmp/vr_a /tmp/vr_b