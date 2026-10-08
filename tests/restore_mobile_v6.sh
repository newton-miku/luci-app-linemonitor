#!/bin/sh
cp /etc/config/network "/tmp/network.bak.$(date +%s)"

echo "=== 恢复前 ==="
uci show network.wan6

echo
echo "=== 启用 wan6（reqprefix 保持 no，只要地址不要 PD）==="
uci set network.wan6.disabled='0'
uci set network.wan6.reqprefix='no'
uci set network.wan6.reqaddress='try'
uci commit network
uci show network.wan6

echo
echo "=== ifup wan6 ==="
ifup wan6 2>&1
sleep 20

echo
echo "=== wan 的 v6 地址 ==="
ip -6 addr show dev wan

echo
echo "=== ubus wan6 状态 ==="
ubus call network.interface.wan6 status 2>&1 | head -32

echo
echo "=== v6 默认路由 ==="
ip -6 route show default

echo
echo "=== 出口B v6 连通性 ==="
V6E=$(ip -6 addr show dev wan scope global 2>/dev/null | awk '/inet6 /{sub(/\/.*/,"",$2); if ($2 !~ /^f[cd]/) { print $2; exit }}')
echo "wan 全局 v6 源: [${V6E:-无}]"
if [ -n "$V6E" ]; then
    echo "-- 阿里 v6 DNS 2400:3200::1 --"
    ping6 -c 3 -W 2 -I "$V6E" 2400:3200::1 2>&1 | tail -3
    echo "-- 出口B v6 DNS 2409:8080:1::1 --"
    ping6 -c 3 -W 2 -I "$V6E" 2409:8080:1::1 2>&1 | tail -3
    echo "-- OpenDNS 2620:0:ccc::2 --"
    ping6 -c 3 -W 2 -I "$V6E" 2620:0:ccc::2 2>&1 | tail -3
fi

echo
echo "=== br-lan 有没有被灌 2409 前缀（不该出现）==="
ip -6 addr show dev br-lan | grep inet6

echo
echo "=== odhcp6c 进程 ==="
ps w | grep odhcp6c | grep -v grep

echo
echo "=== 会不会又出现走 wan 的 v6 默认路由（PD 泄漏）==="
ip -6 route show default | grep wan || echo "OK：没有走 wan 的 v6 默认路由"
