#!/bin/sh
# 诊断 qq.com 这个 HTTP 目标为什么一直 FAIL
CT=4
EX_IF=wan
SRC=$(ip -4 addr show $EX_IF | awk '/inet /{sub(/\/.*/,"",$2); print $2; exit}')
echo "wan 当前源地址 = $SRC"

echo
echo "=== qq.com 解析结果（nslookup 223.5.5.5）==="
nslookup qq.com 223.5.5.5 2>/dev/null | grep -E '^Address'

echo
echo "=== 用第 1 个 IP 直连（当前脚本的做法：http://IP，不带 Host 头）==="
IP1=$(nslookup qq.com 223.5.5.5 2>/dev/null | awk '/^Address [0-9]+: /{print $3; exit}')
echo "IP1=$IP1"
ip rule add from "$SRC" lookup 1 pref 3000 2>/dev/null
i=1
while [ $i -le 3 ]; do
    out=$(curl --interface "$EX_IF" -o /dev/null -s -w '%{time_connect} %{http_code}' --connect-timeout "$CT" "http://$IP1" 2>/dev/null)
    echo "  try$i rc=$? out=$out"
    i=$((i + 1))
done

echo
echo "=== 带上 Host: qq.com ==="
i=1
while [ $i -le 3 ]; do
    out=$(curl --interface "$EX_IF" -o /dev/null -s -w '%{time_connect} %{http_code}' --connect-timeout "$CT" -H 'Host: qq.com' "http://$IP1" 2>/dev/null)
    echo "  try$i rc=$? out=$out"
    i=$((i + 1))
done

echo
echo "=== 逐个 IP 试（TCP 握手即可）==="
for ip in $(nslookup qq.com 223.5.5.5 2>/dev/null | awk '/^Address [0-9]+: /{print $3}'); do
    case "$ip" in *:*) continue ;; esac
    out=$(curl --interface "$EX_IF" -o /dev/null -s -w '%{time_connect} %{http_code}' --connect-timeout "$CT" "http://$ip" 2>/dev/null)
    echo "  $ip rc=$? out=$out"
done
ip rule del from "$SRC" lookup 1 pref 3000 2>/dev/null
