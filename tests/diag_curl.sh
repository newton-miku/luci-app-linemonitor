#!/bin/sh
# 诊断：出口B出口（wan / 源 203.0.113.112）访问 HTTP 目标为什么时通时不通
# 用法：scp 到路由器后 sh /tmp/diag_curl.sh
CT=4
echo "=== wan 地址 ==="
ip -4 addr show wan | grep -E 'inet |state '
echo
echo "=== 相关策略路由 ==="
ip rule | head -8
echo
echo "=== A. curl --interface wan（不给源地址，不带策略路由）==="
DEL=0
ip rule add from 203.0.113.112 lookup 1 pref 3000 2>/dev/null && DEL=1
i=1
while [ $i -le 4 ]; do
    out=$(curl --interface wan -o /dev/null -s -w '%{time_connect} %{http_code}' --connect-timeout "$CT" http://183.3.226.55 2>/dev/null)
    rc=$?
    echo "  try$i rc=$rc out=$out"
    i=$((i + 1))
done
echo
echo "=== B. curl --interface 203.0.113.112（绑源地址）==="
i=1
while [ $i -le 4 ]; do
    out=$(curl --interface 203.0.113.112 -o /dev/null -s -w '%{time_connect} %{http_code}' --connect-timeout "$CT" http://183.3.226.55 2>/dev/null)
    rc=$?
    echo "  try$i rc=$rc out=$out"
    i=$((i + 1))
done
[ "$DEL" = "1" ] && ip rule del from 203.0.113.112 lookup 1 pref 3000 2>/dev/null
echo
echo "=== C. 目标是域名时解析到什么 ==="
nslookup weixin.qq.com 223.5.5.5 2>/dev/null | grep -E '^Address'
nslookup taobao.com 223.5.5.5 2>/dev/null | grep -E '^Address'
