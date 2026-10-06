#!/bin/sh
# 追查 v6 实际连通性、上游 192.168.8.1 身份、以及 eth1 为何拿到电信 PD
echo "=== 1) v6 连通性：本机 → 公网 ==="
echo "--- 默认路由于 pppoe-wan2 ---"
ping6 -c 3 -W 2 2400:3200::1 2>&1 | tail -n 4
echo "--- 显式绑电信源地址 ---"
ping6 -c 3 -W 2 -I 240e:358:a001:8a7e:1093:74c3:28c2:c6a3 2400:3200::1 2>&1 | tail -n 4
echo "--- 绑 pppoe-wan2 接口 ---"
ping6 -c 3 -W 2 -I pppoe-wan2 2400:3200::1 2>&1 | tail -n 4
echo "--- 电信 DNS 240e:f:a::6 ---"
ping6 -c 3 -W 2 240e:f:a::6 2>&1 | tail -n 4

echo
echo "=== 2) v6 出口选择 ==="
ip -6 route get 2400:3200::1 2>&1
echo "--- 以 lan 前缀为源 ---"
ip -6 route get 2400:3200::1 from 240e:359:a052:d00::1 2>&1

echo
echo "=== 3) 上游 192.168.8.1 身份 ==="
ip neigh show dev eth1 | grep -E '192\.168\.8\.1 ' 
echo "--- 同网段其他设备（说明这是个真 LAN 还是点对点）---"
ip neigh show dev eth1 | head -n 15

echo
echo "=== 4) eth1 的 dhcpv6 日志 ==="
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
echo "=== 8) eth1 上的 v6 地址 ==="
ip -6 addr show eth1

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
