#!/bin/sh
# 诊断二：用真实可达目标，区分「线路不通」和「源地址/策略路由不对」
CT=4
WX=117.89.182.41          # weixin.qq.com 解析结果
TB=59.82.121.163          # taobao.com 解析结果

echo "=== eth1 地址 ==="
ip -4 addr show eth1 | grep 'inet '
echo
echo "=== 从 192.168.8.114 看路由 ==="
ip route get "$WX" from 192.168.8.114 iif eth1 2>&1 | head -3
echo
echo "=== 表 1（移动）的内容 ==="
ip route show table 1 | head -8
echo
echo "=== A. curl --interface eth1（源地址由内核选 192.168.8.114）==="
i=1
while [ $i -le 4 ]; do
    out=$(curl --interface eth1 -o /dev/null -s -w '%{time_connect} %{http_code}' --connect-timeout "$CT" "http://$WX" 2>/dev/null)
    echo "  try$i rc=$? out=$out"
    i=$((i + 1))
done
echo
echo "=== B. 不指定接口（走默认路由，即电信）==="
i=1
while [ $i -le 2 ]; do
    out=$(curl -o /dev/null -s -w '%{time_connect} %{http_code}' --connect-timeout "$CT" "http://$WX" 2>/dev/null)
    echo "  try$i rc=$? out=$out"
    i=$((i + 1))
done
echo
echo "=== C. 临时策略路由 from 192.168.8.114 + curl --interface eth1 ==="
ip rule add from 192.168.8.114 lookup 1 pref 3000 2>/dev/null
i=1
while [ $i -le 4 ]; do
    out=$(curl --interface eth1 -o /dev/null -s -w '%{time_connect} %{http_code}' --connect-timeout "$CT" "http://$WX" 2>/dev/null)
    echo "  try$i rc=$? out=$out"
    i=$((i + 1))
done
ip rule del from 192.168.8.114 lookup 1 pref 3000 2>/dev/null
echo
echo "=== D. 同样条件下 ping（对照：ICMP 一直成功）==="
ping -I eth1 -c 3 -W 2 "$WX" 2>&1 | tail -2
