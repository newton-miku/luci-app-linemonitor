#!/bin/sh
# diag_topo.sh — 看清 eth0/eth1/br-lan/pppoe-wan2 的真实角色
echo "=== brctl show ==="
brctl show 2>/dev/null
echo
echo "=== ip -br link ==="
ip -br link
echo
echo "=== ip -br addr ==="
ip -br addr
echo
echo "=== uci network device/interface ==="
uci show network 2>/dev/null | grep -E '=(device|interface)$|\.(ifname|ports|type|proto|device|master)='
echo
echo "=== /sys/class/net ==="
ls /sys/class/net
echo
echo "=== swconfig ==="
swconfig list 2>/dev/null
swconfig dev switch0 show 2>/dev/null | head -30
