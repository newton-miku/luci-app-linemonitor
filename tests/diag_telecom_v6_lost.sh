#!/bin/sh
echo "=== pppoe-wan v6 地址 ==="
ip -6 addr show dev pppoe-wan

echo
echo "=== wan v6 地址 ==="
ip -6 addr show dev wan

echo
echo "=== v6_src_of 实测（line_monitor.sh 用的取法）==="
for d in pppoe-wan wan; do
  s=$(ip -6 addr show dev "$d" scope global 2>/dev/null | awk '/inet6 /{sub(/\/.*/,"",$2); if ($2 !~ /^f[cd]/) { print $2; exit }}')
  echo "$d -> [${s:-无}]"
done

echo
echo "=== ubus wan2_6 status ==="
ubus call network.interface.wan2_6 status 2>&1 | head -45

echo
echo "=== pppoe-wan v4 地址与链路 ==="
ip -4 addr show dev pppoe-wan
ip link show pppoe-wan

echo
echo "=== 出口A v6 手工连通性测试 ==="
V6P=$(ip -6 addr show dev pppoe-wan scope global 2>/dev/null | awk '/inet6 /{sub(/\/.*/,"",$2); if ($2 !~ /^f[cd]/) { print $2; exit }}')
echo "pppoe-wan 全局 v6 源: [${V6P:-无}]"
if [ -n "$V6P" ]; then
  ping6 -c 3 -W 2 -I "$V6P" 2400:3200::1 2>&1 | tail -3
  ping6 -c 3 -W 2 -I "$V6P" 240e:954:0:1c:3::29 2>&1 | tail -3
else
  echo "无全局 v6 源，测不了"
fi

echo
echo "=== odhcp6c 进程 ==="
ps w | grep odhcp6c | grep -v grep

echo
echo "=== 出口A v6 前缀（ubus 全局）==="
ubus call network.interface.wan2_6 status 2>&1 | grep -A4 'ipv6-prefix' | head -20

echo
echo "=== 系统日志里 odhcp6c/wan2_6 相关最近 25 行 ==="
logread 2>/dev/null | grep -iE 'odhcp6c|wan2_6|wan6' | tail -25
