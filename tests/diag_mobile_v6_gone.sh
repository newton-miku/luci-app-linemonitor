#!/bin/sh
echo "=== 1) wan6 接口配置 ==="
uci show network.wan6 2>/dev/null

echo
echo "=== 2) 所有接口的 proto/device/disabled ==="
for i in $(uci show network 2>/dev/null | grep '=interface$' | cut -d. -f2 | cut -d= -f1); do
    p=$(uci -q get network.$i.proto)
    dev=$(uci -q get network.$i.device)
    d=$(uci -q get network.$i.disabled)
    printf '%-10s proto=%-8s device=%-12s disabled=%s\n' "$i" "${p:--}" "${dev:--}" "${d:-0}"
done

echo
echo "=== 3) eth1 的 v6 地址（移动口）==="
ip -6 addr show dev eth1

echo
echo "=== 4) br-lan 的 v6 地址 ==="
ip -6 addr show dev br-lan | grep -E 'inet6|state'

echo
echo "=== 5) pppoe-wan2 的 v6 地址（电信口）==="
ip -6 addr show dev pppoe-wan2 | grep inet6

echo
echo "=== 6) ubus wan6 状态 ==="
ubus call network.interface.wan6 status 2>&1 | head -25

echo
echo "=== 7) ubus wan2_6 状态 ==="
ubus call network.interface.wan2_6 status 2>&1 | head -25

echo
echo "=== 8) odhcp6c / odhcpd 进程 ==="
ps w | grep -E 'odhcp6c|odhcpd' | grep -v grep

echo
echo "=== 9) v6 默认路由 ==="
ip -6 route show default

echo
echo "=== 10) v6 策略规则（前 15 条）==="
ip -6 rule show 2>/dev/null | head -15

echo
echo "=== 11) 移动线路连通性 ==="
echo "-- ping 上游网关 192.168.8.1 --"
ping -c 3 -W 2 192.168.8.1 2>&1 | tail -3
echo "-- eth1 v4 地址 --"
ip -4 addr show dev eth1 | grep inet
ETH4=$(ip -4 addr show dev eth1 | awk '/inet /{sub(/\/.*/,"",$2); print $2; exit}')
echo "-- 用 $ETH4 源地址 ping 223.5.5.5 --"
[ -n "$ETH4" ] && ping -c 3 -W 2 -I "$ETH4" 223.5.5.5 2>&1 | tail -3

echo
echo "=== 12) 电信 v6 连通性 ==="
SRC6=$(ip -6 addr show dev pppoe-wan2 scope global 2>/dev/null | awk '/inet6 /{sub(/\/.*/,"",$2); if ($2 !~ /^f[cd]/) { print $2; exit }}')
echo "pppoe-wan2 源地址: ${SRC6:-无}"
[ -n "$SRC6" ] && ping6 -c 3 -W 2 -I "$SRC6" 2400:3200::1 2>&1 | tail -3

echo
echo "=== 13) 看板用的移动 v6 源地址 ==="
V6E=$(ip -6 addr show dev eth1 scope global 2>/dev/null | awk '/inet6 /{sub(/\/.*/,"",$2); if ($2 !~ /^f[cd]/) { print $2; exit }}')
echo "eth1 全局 v6 源: [${V6E:-无}]"

echo
echo "=== 14) history.log 最新一行里的 v6 键 ==="
tail -n 1 /www/lm/history.log 2>/dev/null | tr ' ' '\n' | grep -E 'v6-' | head -12

echo
echo "=== 15) 移动出口的 v6 目标在最近 5 行的表现 ==="
tail -n 5 /www/lm/history.log 2>/dev/null | tr ' ' '\n' | grep '^v6-eth1|' | sort -u | head -8

echo
echo "=== 16) 上游 eth1 的 RA ==="
timeout 12 tcpdump -i eth1 -n -c 3 'icmp6 and ip6[40]==134' 2>&1 | tail -20
