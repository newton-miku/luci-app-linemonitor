#!/bin/sh
# 掐断 eth1 上游灌进来的电信 PD，并删掉残留的 relay master
echo "=== 0) 备份 ==="
BK=/tmp/uci-backup2-$(date +%s).txt
uci export > "$BK"
echo "backup -> $BK"

echo
echo "=== 1) 改前：v6 默认路由 ==="
ip -6 route show default

echo
echo "=== 2) wan6 不请求 PD + 删掉 wan2_6 的 relay master ==="
uci set network.wan6.reqprefix='no'
uci commit network
uci delete dhcp.wan2_6.master 2>/dev/null
uci commit dhcp
echo "done"
echo "--- network.wan6 ---"
uci show network.wan6
echo "--- dhcp.wan2_6 ---"
uci show dhcp.wan2_6

echo
echo "=== 3) reload network ==="
/etc/init.d/network reload
sleep 35

echo
echo "=== 4) 改后：v6 默认路由 ==="
ip -6 route show default

echo
echo "=== 5) br-lan 地址 ==="
ip -6 addr show br-lan | grep inet6

echo
echo "=== 6) odhcpd/odhcp6c 进程 ==="
ps w | grep -E 'odhcpd|odhcp6c' | grep -v grep

echo
echo "=== 7) 从路由器测 v6 ==="
curl -6 -s -o /dev/null -w "curl6 http=%{http_code} time=%{time_total}\n" --max-time 10 https://ipv6.baidu.com
echo "--- ping6 电信DNS ---"
ping6 -c 3 -W 3 240e:f:a::6 2>&1 | tail -n 3

echo
echo "=== 8) odhcpd 日志（最近 8 条） ==="
logread | grep -i odhcpd | tail -n 8
