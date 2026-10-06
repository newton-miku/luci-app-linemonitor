#!/bin/sh
# 重算 network，清掉指向 eth1 的伪默认路由，确认 v6 真正走电信
echo "=== 1) 改前：v6 默认路由 ==="
ip -6 route show default

echo
echo "=== 2) reload network ==="
/etc/init.d/network reload
sleep 30

echo
echo "=== 3) 改后：v6 默认路由 ==="
ip -6 route show default

echo
echo "=== 4) table main 的 v6 路由（前 40 条） ==="
ip -6 route show | head -n 40

echo
echo "=== 5) ip -6 rule ==="
ip -6 rule show | head -n 15

echo
echo "=== 6) wan6 的 v6 前缀 ==="
ubus call network.interface.wan6 status 2>/dev/null | grep -A 30 ipv6

echo
echo "=== 7) wan2_6 的 v6 前缀 ==="
ubus call network.interface.wan2_6 status 2>/dev/null | grep -A 30 ipv6

echo
echo "=== 8) br-lan 地址 ==="
ip -6 addr show br-lan | grep inet6

echo
echo "=== 9) 从路由器测电信 v6 ==="
curl -6 -s -o /dev/null -w "curl6 http=%{http_code} time=%{time_total}\n" --max-time 10 https://ipv6.baidu.com
curl -4 -s -o /dev/null -w "curl4 http=%{http_code} time=%{time_total}\n" --max-time 10 https://www.baidu.com

echo
echo "=== 10) odhcpd 日志（最近 10 条） ==="
logread | grep -i odhcpd | tail -n 10

echo
echo "=== 11) odhcpd 进程 ==="
ps w | grep -E 'odhcpd|odhcp6c' | grep -v grep
