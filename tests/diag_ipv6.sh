#!/bin/sh
# 诊断移动（eth1 / 蜂窝 CPE）侧 IPv6 为什么不通
echo "===== 1. 全部 IPv6 地址 ====="
ip -6 addr show

echo
echo "===== 2. IPv6 路由表 ====="
ip -6 route show

echo
echo "===== 3. 默认路由（各表）====="
ip -6 route show table all | grep -i default

echo
echo "===== 4. 接口 up/down ====="
ip link show eth1 | head -3
ip link show br-lan | head -3

echo
echo "===== 5. eth1 的 v6 状态 (ifstatus wan6) ====="
ifstatus wan6 2>&1 | head -60

echo
echo "===== 6. 相关 uci 配置 ====="
uci show network | grep -Ei 'wan6|wan2|wan_6|ipv6|proto|device|ifname' | head -60

echo
echo "===== 7. DHCPv6 客户端进程 ====="
ps w | grep -Ei 'odhcp6c|dhcp6c' | grep -v grep

echo
echo "===== 8. eth1 上的 RA / 邻居 ====="
ip -6 neigh show dev eth1 2>&1 | head
echo "--- 尝试 ping CPE 网关 v6 ---"
ping6 -c 2 -W 2 -I eth1 fe80::1 2>&1 | tail -3

echo
echo "===== 9. 移动 v6 目标连通性 ====="
echo "--- 不指定源 ---"
ping6 -c 2 -W 2 2409:8080::8 2>&1 | tail -3
echo "--- 指定 eth1 ---"
ping6 -c 2 -W 2 -I eth1 2409:8080::8 2>&1 | tail -3

echo
echo "===== 10. 电信 v6 对比 ====="
ping6 -c 2 -W 2 2400:3200::1 2>&1 | tail -3

echo
echo "===== 11. odhcp6c 日志 ====="
logread 2>/dev/null | grep -iE 'odhcp6c|wan6|dhcpv6' | tail -20
