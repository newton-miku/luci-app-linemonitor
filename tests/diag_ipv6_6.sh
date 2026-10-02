#!/bin/sh
# 第五轮：把 wan6 的 metric 调大（而非禁用）能否解决问题？并确认最终状态
echo "===== 现状 ====="
uci show network.wan6
ip -6 route show | grep -c default
echo

echo "===== 尝试：只调大 wan6 的 metric，不禁用它 ====="
uci set network.wan6.metric='2000'
uci commit network
ifup wan6 2>&1
sleep 8
echo "--- 默认 v6 路由 ---"
ip -6 route show | grep default
echo "--- br-lan 地址 ---"
ip -6 addr show br-lan | grep 'scope global'
echo "--- 测电信 v6 ---"
ping6 -c 2 -W 2 2400:3200::1 2>&1 | tail -2
echo "--- 测 eth1 上的 v6 ---"
ping6 -c 2 -W 2 -I eth1 2409:8080::8 2>&1 | tail -2

echo
echo "===== 回滚到 metric=10 ====="
uci set network.wan6.metric='10'
uci commit network
ifup wan6 2>&1
sleep 6
ip -6 route show | grep default
ping6 -c 2 -W 2 2400:3200::1 2>&1 | tail -2
echo "已回滚"
