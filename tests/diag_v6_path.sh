#!/bin/sh
# 追查 v6 实际连通性、上游 203.0.113.1 身份、以及 wan 为何拿到出口A PD
echo "=== 1) v6 连通性：本机 → 公网 ==="
echo "--- 默认路由于 pppoe-wan ---"
ping6 -c 3 -W 2 2400:3200::1 2>&1 | tail -n 4
echo "--- 显式绑出口A源地址 ---"
ping6 -c 3 -W 2 -I 2001:db8:1234:5678 2400:3200::1 2>&1 | tail -n 4
echo "--- 绑 pppoe-wan 接口 ---"
ping6 -c 3 -W 2 -I pppoe-wan 2400:3200::1 2>&1 | tail -n 4
echo "--- 出口A DNS 240e:f:a::6 ---"
ping6 -c 3 -W 2 240e:f:a::6 2>&1 | tail -n 4

echo
echo "=== 2) v6 出口选择 ==="
ip -6 route get 2400:3200::1 2>&1
echo "--- 以 lan 前缀为源 ---"
ip -6 route get 2400:3200::1 from 2001:db8:9abc:def0::1 2>&1

echo
echo "=== 3) 上游 203.0.113.1 身份 ==="
ip neigh show dev wan | grep -E '192\.168\.8\.1 ' 
echo "--- 同网段其他设备（说明这是个真 LAN 还是点对点）---"
ip neigh show dev wan | head -n 15

echo
echo "=== 4) wan 的 dhcpv6 日志 ==="
logread | grep -i odhcp6c | tail -n 25
echo "--- odhcp6c 进程 ---"
ps w | grep '[o]dhcp6c'

echo
echo "=== 5) odhcpd 配置 ==="
uci show odhcpd 2>/dev/null | head -n 40

echo
echo "=== 6) br-lan 的 v6 地址 ==="
ip -6 addr show br-lan

echo
echo "=== 7) v6 地址冲突/DAD 日志 ==="
logread | grep -iE 'duplicate|conflict|dad|DAD' | tail -n 15

echo
echo "=== 8) wan 上的 v6 地址 ==="
ip -6 addr show wan

echo
echo "=== 9) 所有 v6 默认路由与表 4 ==="
echo "--- main ---"
ip -6 route show default
echo "--- table 4 ---"
ip -6 route show table 4
echo "--- table 2 ---"
ip -6 route show table 2

echo
echo "=== 10) 用 curl 测 v6 出网（如果有 curl）==="
which curl >/dev/null 2>&1 && curl -6 -s -m 8 -o /dev/null -w "v6 curl http_code=%{http_code} time=%{time_total}\n" https://ipv6.baidu.com 2>&1 || echo "(no curl)"
which wget >/dev/null 2>&1 && wget -6 -q -O /dev/null -T 8 http://[2400:3200::1] 2>&1 | head -n 3
echo "--- v4 对照 ---"
which curl >/dev/null 2>&1 && curl -4 -s -m 8 -o /dev/null -w "v4 curl http_code=%{http_code} time=%{time_total}\n" https://www.baidu.com 2>&1
